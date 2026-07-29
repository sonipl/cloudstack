// Licensed to the Apache Software Foundation (ASF) under one or more
// contributor license agreements. See the NOTICE file distributed with
// this work for additional information regarding copyright ownership.
// The ASF licenses this file to You under the Apache License, Version 2.0
// (the "License"); you may not use this file except in compliance with
// the License.  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package org.apache.cloudstack.hci.ceph;

import java.util.List;

import org.apache.cloudstack.framework.config.ConfigKey;
import org.apache.cloudstack.framework.config.Configurable;
import org.apache.cloudstack.hci.ceph.api.response.HciCephHealthResponse;

import com.cloud.storage.StoragePool;
import com.cloud.utils.component.PluggableService;

/**
 * Manager providing vSAN-like awareness of the Ceph clusters that back
 * CloudStack RBD primary storage pools in a hyperconverged (HCI) deployment.
 * It periodically polls Ceph health and exposes it to allocators, APIs and
 * the alert subsystem.
 */
public interface CephHciManager extends PluggableService, Configurable {

    ConfigKey<Boolean> CephHciHealthEnforcement = new ConfigKey<>("Advanced", Boolean.class,
            "ceph.hci.allocation.enforce.health", "true",
            "When true, RBD primary storage pools backed by an unhealthy Ceph cluster are excluded from VM/volume "
                    + "allocation, similar to vSAN object placement on a degraded cluster.",
            true, ConfigKey.Scope.Global);

    ConfigKey<String> CephHciAcceptedHealthStates = new ConfigKey<>("Advanced", String.class,
            "ceph.hci.health.accepted.states", "HEALTH_OK,HEALTH_WARN",
            "Comma separated Ceph overall health states that are still considered acceptable for allocation.",
            true, ConfigKey.Scope.Global);

    ConfigKey<Integer> CephHciHealthCheckInterval = new ConfigKey<>("Advanced", Integer.class,
            "ceph.hci.health.check.interval", "300",
            "Interval in seconds between Ceph cluster health polls for HCI storage pools. 0 disables polling.",
            true, ConfigKey.Scope.Global);

    ConfigKey<String> CephHciMonSshUser = new ConfigKey<>("Advanced", String.class,
            "ceph.hci.monitor.ssh.user", "root",
            "SSH user used by the management server to run 'ceph status' on the Ceph monitor of an HCI cluster.",
            true, ConfigKey.Scope.Global);

    ConfigKey<Integer> CephHciMonSshPort = new ConfigKey<>("Advanced", Integer.class,
            "ceph.hci.monitor.ssh.port", "22",
            "SSH port of the Ceph monitor hosts.",
            true, ConfigKey.Scope.Global);

    ConfigKey<String> CephHciMonSshPassword = new ConfigKey<>("Secure", String.class,
            "ceph.hci.monitor.ssh.password", "",
            "SSH password for the Ceph monitor user. If empty, the configured SSH private key is used.",
            true, ConfigKey.Scope.Global);

    ConfigKey<String> CephHciMonSshPrivateKeyPath = new ConfigKey<>("Advanced", String.class,
            "ceph.hci.monitor.ssh.privatekey.path", "/root/.ssh/id_rsa",
            "Path on the management server to the SSH private key used to reach Ceph monitors when no password is set.",
            true, ConfigKey.Scope.Global);

    /**
     * Returns the last known health of the Ceph cluster backing the given
     * pool, or null if the pool is not RBD-backed or no data is available yet.
     */
    CephClusterHealth getClusterHealth(StoragePool pool);

    /**
     * vSAN-like placement rule: decides whether a pool is eligible for new
     * allocations based on the health of its backing Ceph cluster. Non-RBD
     * pools and disabled enforcement always return true.
     */
    boolean isPoolAllocationAllowed(StoragePool pool);

    /**
     * Returns health responses for all known Ceph-backed storage pools,
     * optionally scoped by zone.
     */
    List<HciCephHealthResponse> listHealth(Long zoneId);

    /**
     * Forces an on-demand refresh of the Ceph health cache.
     */
    void refreshHealth();
}
