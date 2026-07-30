// Licensed to the Apache Software Foundation (ASF) under one or more
// contributor license agreements. See the NOTICE file distributed with
// this work for additional information regarding copyright ownership.
// The ASF licenses this file to You under the Apache License, Version 2.0
// (the "License"); you may not use this file except in compliance with
// the License. You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package org.apache.cloudstack.hci.ceph;

import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

import javax.inject.Inject;

import org.apache.cloudstack.alert.AlertService;
import org.apache.cloudstack.framework.config.ConfigKey;
import org.apache.cloudstack.hci.ceph.api.ListHciCephHealthCmd;
import org.apache.cloudstack.hci.ceph.api.RefreshHciCephHealthCmd;
import org.apache.cloudstack.hci.ceph.api.response.HciCephHealthResponse;
import org.apache.cloudstack.storage.datastore.db.PrimaryDataStoreDao;
import org.apache.cloudstack.storage.datastore.db.StoragePoolVO;
import org.apache.commons.lang3.StringUtils;

import com.cloud.alert.AlertManager;
import com.cloud.dc.ClusterVO;
import com.cloud.dc.DataCenterVO;
import com.cloud.dc.dao.ClusterDao;
import com.cloud.dc.dao.DataCenterDao;
import com.cloud.storage.Storage.StoragePoolType;
import com.cloud.storage.StoragePool;
import com.cloud.storage.StoragePoolStatus;
import com.cloud.utils.Pair;
import com.cloud.utils.component.ManagerBase;
import com.cloud.utils.concurrency.NamedThreadFactory;
import com.cloud.utils.ssh.SshHelper;

public class CephHciManagerImpl extends ManagerBase implements CephHciManager {

    private static final String CEPH_STATUS_COMMAND = "ceph status -f json";
    private static final int SSH_COMMAND_TIMEOUT_MS = 30000;

    @Inject
    private PrimaryDataStoreDao storagePoolDao;
    @Inject
    private DataCenterDao dataCenterDao;
    @Inject
    private ClusterDao clusterDao;
    @Inject
    private AlertManager alertManager;

    /**
     * Health cache keyed by normalized Ceph cluster endpoint (sorted mons + port).
     */
    private final Map<String, CephClusterHealth> healthCache = new ConcurrentHashMap<>();

    private ScheduledExecutorService healthCheckExecutor;

    @Override
    public boolean start() {
        int interval = CephHciHealthCheckInterval.value();
        if (interval > 0) {
            healthCheckExecutor = Executors.newSingleThreadScheduledExecutor(new NamedThreadFactory("Ceph-HCI-Health"));
            healthCheckExecutor.scheduleWithFixedDelay(this::refreshHealthSafely, 0, interval, TimeUnit.SECONDS);
            logger.info("Started Ceph HCI health checker with interval [{}]s.", interval);
        } else {
            logger.info("Ceph HCI health check interval is 0, background polling disabled.");
        }
        return true;
    }

    @Override
    public boolean stop() {
        if (healthCheckExecutor != null) {
            healthCheckExecutor.shutdownNow();
            try {
                healthCheckExecutor.awaitTermination(5, TimeUnit.SECONDS);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            healthCheckExecutor = null;
        }
        return true;
    }

    /**
     * Normalizes RBD hostAddress values that may list multiple MONs
     * (comma/semicolon/whitespace separated) into a stable cluster key.
     */
    protected static String clusterKeyFor(StoragePool pool) {
        List<String> mons = parseMonitorHosts(pool.getHostAddress());
        String monPart = mons.isEmpty() ? String.valueOf(pool.getHostAddress()) : String.join(",", mons);
        return monPart + ":" + pool.getPort();
    }

    /**
     * Parses CloudStack RBD monitor host strings into individual hostnames/IPs.
     * Accepts comma, semicolon, or whitespace separators; strips optional
     * {@code host:port} suffixes so SSH uses the dedicated SSH port config.
     */
    protected static List<String> parseMonitorHosts(String hostAddress) {
        List<String> hosts = new ArrayList<>();
        if (StringUtils.isBlank(hostAddress)) {
            return hosts;
        }
        for (String token : hostAddress.trim().split("[,;\\s]+")) {
            if (StringUtils.isBlank(token)) {
                continue;
            }
            String host = token.trim();
            // Strip [ipv6]:port or host:port for SSH target selection.
            if (host.startsWith("[")) {
                int end = host.indexOf(']');
                if (end > 0) {
                    host = host.substring(1, end);
                }
            } else {
                int colon = host.lastIndexOf(':');
                if (colon > 0 && host.indexOf(':') == colon) {
                    // single colon → host:port (not bare IPv6)
                    String maybePort = host.substring(colon + 1);
                    if (maybePort.chars().allMatch(Character::isDigit)) {
                        host = host.substring(0, colon);
                    }
                }
            }
            if (StringUtils.isNotBlank(host) && !hosts.contains(host)) {
                hosts.add(host);
            }
        }
        // Stable key regardless of MON ordering in the pool record.
        hosts.sort(String::compareTo);
        return hosts;
    }

    protected Map<String, List<StoragePoolVO>> listRbdPoolsByCluster() {
        Map<String, List<StoragePoolVO>> result = new HashMap<>();
        List<StoragePoolVO> pools = storagePoolDao.listByStatus(StoragePoolStatus.Up);
        for (StoragePoolVO pool : pools) {
            if (StoragePoolType.RBD.equals(pool.getPoolType())) {
                result.computeIfAbsent(clusterKeyFor(pool), k -> new ArrayList<>()).add(pool);
            }
        }
        return result;
    }

    private void refreshHealthSafely() {
        try {
            refreshHealth();
        } catch (Throwable t) {
            logger.warn("Unexpected error during Ceph HCI health refresh.", t);
        }
    }

    @Override
    public void refreshHealth() {
        Map<String, List<StoragePoolVO>> poolsByCluster = listRbdPoolsByCluster();
        if (poolsByCluster.isEmpty()) {
            healthCache.clear();
            logger.trace("No RBD primary storage pools found, skipping Ceph health refresh.");
            return;
        }
        Set<String> seen = new HashSet<>();
        for (Map.Entry<String, List<StoragePoolVO>> entry : poolsByCluster.entrySet()) {
            String clusterKey = entry.getKey();
            seen.add(clusterKey);
            StoragePoolVO pool = entry.getValue().get(0);
            CephClusterHealth previous = healthCache.get(clusterKey);
            CephClusterHealth current = pollClusterHealth(clusterKey, pool);
            healthCache.put(clusterKey, current);
            alertOnHealthTransition(previous, current, entry.getValue());
        }
        healthCache.keySet().retainAll(seen);
    }

    protected CephClusterHealth pollClusterHealth(String clusterKey, StoragePoolVO pool) {
        String user = CephHciMonSshUser.value();
        int port = CephHciMonSshPort.value();
        String password = StringUtils.defaultIfBlank(CephHciMonSshPassword.value(), null);
        File keyFile = null;
        if (password == null) {
            String keyPath = StringUtils.defaultIfBlank(CephHciMonSshPrivateKeyPath.value(), null);
            if (keyPath != null) {
                keyFile = new File(keyPath);
            }
        }

        List<String> mons = parseMonitorHosts(pool.getHostAddress());
        if (mons.isEmpty() && StringUtils.isNotBlank(pool.getHostAddress())) {
            mons = List.of(pool.getHostAddress().trim());
        }
        if (mons.isEmpty()) {
            return CephClusterHealth.error(clusterKey, "No Ceph monitor hosts configured on storage pool");
        }

        List<String> errors = new ArrayList<>();
        for (String monHost : mons) {
            try {
                Pair<Boolean, String> result = SshHelper.sshExecute(monHost, port, user, keyFile, password,
                        CEPH_STATUS_COMMAND, SSH_COMMAND_TIMEOUT_MS);
                if (result.first()) {
                    return CephClusterHealth.fromStatusJson(clusterKey, result.second());
                }
                errors.add(monHost + ": " + result.second());
                logger.warn("Failed to collect Ceph health from monitor [{}] of [{}]: {}", monHost, clusterKey,
                        result.second());
            } catch (Exception e) {
                errors.add(monHost + ": " + e.getMessage());
                logger.warn("Error collecting Ceph health from monitor [{}] of [{}]: {}", monHost, clusterKey,
                        e.getMessage(), e);
            }
        }
        return CephClusterHealth.error(clusterKey, "All monitors unreachable: " + String.join("; ", errors));
    }

    private void alertOnHealthTransition(CephClusterHealth previous, CephClusterHealth current, List<StoragePoolVO> pools) {
        if (current == null) {
            return;
        }
        StoragePoolVO pool = pools.get(0);
        boolean wasAcceptable = previous == null || previous.isHealthy(acceptedHealthStates());
        boolean isAcceptable = current.isHealthy(acceptedHealthStates());
        if (wasAcceptable == isAcceptable) {
            return;
        }
        if (!isAcceptable) {
            alertManager.sendAlert(AlertService.AlertType.ALERT_TYPE_STORAGE_MISC, pool.getDataCenterId(), pool.getPodId(),
                    "Ceph cluster backing HCI storage is unhealthy",
                    String.format("Ceph cluster [%s] backing RBD storage pool(s) [%s] reports [%s]. New allocations "
                                    + "on these pools are suspended until health returns to an accepted state.",
                            current.getClusterKey(),
                            pools.stream().map(StoragePoolVO::getName).collect(Collectors.joining(", ")),
                            current.isReachable() ? current.getOverallStatus() : "unreachable: " + current.getError()));
        } else {
            alertManager.sendAlert(AlertService.AlertType.ALERT_TYPE_STORAGE_MISC, pool.getDataCenterId(), pool.getPodId(),
                    "Ceph cluster backing HCI storage recovered",
                    String.format("Ceph cluster [%s] backing RBD storage pool(s) [%s] recovered to [%s].",
                            current.getClusterKey(),
                            pools.stream().map(StoragePoolVO::getName).collect(Collectors.joining(", ")),
                            current.getOverallStatus()));
        }
    }

    protected Set<String> acceptedHealthStates() {
        return Arrays.stream(CephHciAcceptedHealthStates.value().split(","))
                .map(String::trim)
                .filter(StringUtils::isNotBlank)
                .collect(Collectors.toSet());
    }

    @Override
    public CephClusterHealth getClusterHealth(StoragePool pool) {
        if (pool == null || !StoragePoolType.RBD.equals(pool.getPoolType())) {
            return null;
        }
        return healthCache.get(clusterKeyFor(pool));
    }

    @Override
    public boolean isPoolAllocationAllowed(StoragePool pool) {
        if (!CephHciHealthEnforcement.value()) {
            return true;
        }
        if (pool == null || !StoragePoolType.RBD.equals(pool.getPoolType())) {
            return true;
        }
        CephClusterHealth health = getClusterHealth(pool);
        if (health == null) {
            // No health data yet (e.g. polling disabled or first cycle pending);
            // fail open so a monitoring outage does not block provisioning.
            logger.debug("No Ceph health data available for pool [{}], allowing allocation.", pool.getName());
            return true;
        }
        boolean allowed = health.isHealthy(acceptedHealthStates());
        if (!allowed) {
            logger.warn("Excluding RBD pool [{}] from allocation: Ceph cluster [{}] is [{}].",
                    pool.getName(), health.getClusterKey(),
                    health.isReachable() ? health.getOverallStatus() : "unreachable: " + health.getError());
        }
        return allowed;
    }

    @Override
    public List<HciCephHealthResponse> listHealth(Long zoneId) {
        List<HciCephHealthResponse> responses = new ArrayList<>();
        for (Map.Entry<String, List<StoragePoolVO>> entry : listRbdPoolsByCluster().entrySet()) {
            for (StoragePoolVO pool : entry.getValue()) {
                if (zoneId != null && pool.getDataCenterId() != zoneId) {
                    continue;
                }
                responses.add(toResponse(pool, healthCache.get(entry.getKey())));
            }
        }
        return responses;
    }

    private HciCephHealthResponse toResponse(StoragePoolVO pool, CephClusterHealth health) {
        HciCephHealthResponse response = new HciCephHealthResponse();
        response.setObjectName("hcicephhealth");
        response.setStoragePoolId(pool.getUuid());
        response.setStoragePoolName(pool.getName());
        DataCenterVO zone = dataCenterDao.findById(pool.getDataCenterId());
        if (zone != null) {
            response.setZoneId(zone.getUuid());
        }
        if (pool.getClusterId() != null) {
            ClusterVO cluster = clusterDao.findById(pool.getClusterId());
            if (cluster != null) {
                response.setClusterId(cluster.getUuid());
            }
        }
        response.setCephCluster(clusterKeyFor(pool));
        response.setAllocationAllowed(isPoolAllocationAllowed(pool));
        if (health != null) {
            response.setHealthStatus(health.isReachable() ? health.getOverallStatus() : "UNKNOWN");
            response.setOsdsTotal(health.getNumOsds());
            response.setOsdsUp(health.getNumOsdsUp());
            response.setOsdsIn(health.getNumOsdsIn());
            response.setPlacementGroups(health.getNumPgs());
            response.setMonitors(health.getNumMons());
            response.setQuorumSize(health.getQuorumSize());
            response.setOsdDegraded(health.hasOsdDegradation());
            response.setLastChecked(new Date(health.getLastChecked()));
            response.setError(health.getError());
        } else {
            response.setHealthStatus("UNKNOWN");
        }
        return response;
    }

    @Override
    public List<Class<?>> getCommands() {
        List<Class<?>> cmdList = new ArrayList<>();
        cmdList.add(ListHciCephHealthCmd.class);
        cmdList.add(RefreshHciCephHealthCmd.class);
        return cmdList;
    }

    @Override
    public String getConfigComponentName() {
        return CephHciManager.class.getSimpleName();
    }

    @Override
    public ConfigKey<?>[] getConfigKeys() {
        return new ConfigKey<?>[] {CephHciHealthEnforcement, CephHciAcceptedHealthStates, CephHciHealthCheckInterval,
                CephHciMonSshUser, CephHciMonSshPort, CephHciMonSshPassword, CephHciMonSshPrivateKeyPath};
    }
}
