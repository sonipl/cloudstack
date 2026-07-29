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

import java.util.Set;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

/**
 * Immutable snapshot of a Ceph cluster's health as reported by
 * {@code ceph status -f json}, used to make vSAN-like placement and
 * alerting decisions for RBD-backed primary storage pools.
 */
public class CephClusterHealth {

    public static final String HEALTH_OK = "HEALTH_OK";
    public static final String HEALTH_WARN = "HEALTH_WARN";
    public static final String HEALTH_ERR = "HEALTH_ERR";

    private final String clusterKey;
    private final String overallStatus;
    private final int numOsds;
    private final int numOsdsUp;
    private final int numOsdsIn;
    private final int numPgs;
    private final int numMons;
    private final int quorumSize;
    private final long lastChecked;
    private final String error;

    public CephClusterHealth(String clusterKey, String overallStatus, int numOsds, int numOsdsUp, int numOsdsIn,
            int numPgs, int numMons, int quorumSize, long lastChecked, String error) {
        this.clusterKey = clusterKey;
        this.overallStatus = overallStatus;
        this.numOsds = numOsds;
        this.numOsdsUp = numOsdsUp;
        this.numOsdsIn = numOsdsIn;
        this.numPgs = numPgs;
        this.numMons = numMons;
        this.quorumSize = quorumSize;
        this.lastChecked = lastChecked;
        this.error = error;
    }

    public static CephClusterHealth error(String clusterKey, String error) {
        return new CephClusterHealth(clusterKey, null, 0, 0, 0, 0, 0, 0, System.currentTimeMillis(), error);
    }

    /**
     * Parses the output of {@code ceph status -f json}. Tolerant to schema
     * differences between Ceph releases (health.status vs health.overall_status).
     */
    public static CephClusterHealth fromStatusJson(String clusterKey, String json) {
        JsonObject root = JsonParser.parseString(json).getAsJsonObject();

        String status = null;
        if (root.has("health") && root.get("health").isJsonObject()) {
            JsonObject health = root.getAsJsonObject("health");
            if (health.has("status")) {
                status = health.get("status").getAsString();
            } else if (health.has("overall_status")) {
                status = health.get("overall_status").getAsString();
            }
        }

        int numOsds = 0;
        int numOsdsUp = 0;
        int numOsdsIn = 0;
        if (root.has("osdmap") && root.get("osdmap").isJsonObject()) {
            JsonObject osdmap = root.getAsJsonObject("osdmap");
            if (osdmap.has("osdmap") && osdmap.get("osdmap").isJsonObject()) {
                osdmap = osdmap.getAsJsonObject("osdmap");
            }
            numOsds = osdmap.has("num_osds") ? osdmap.get("num_osds").getAsInt() : 0;
            numOsdsUp = osdmap.has("num_up_osds") ? osdmap.get("num_up_osds").getAsInt() : 0;
            numOsdsIn = osdmap.has("num_in_osds") ? osdmap.get("num_in_osds").getAsInt() : 0;
        }

        int numPgs = 0;
        if (root.has("pgmap") && root.get("pgmap").isJsonObject()) {
            JsonObject pgmap = root.getAsJsonObject("pgmap");
            numPgs = pgmap.has("num_pgs") ? pgmap.get("num_pgs").getAsInt() : 0;
        }

        int numMons = 0;
        if (root.has("monmap") && root.get("monmap").isJsonObject()) {
            JsonObject monmap = root.getAsJsonObject("monmap");
            numMons = monmap.has("num_mons") ? monmap.get("num_mons").getAsInt() : 0;
        }

        int quorumSize = 0;
        if (root.has("quorum") && root.get("quorum").isJsonArray()) {
            quorumSize = root.getAsJsonArray("quorum").size();
        }

        return new CephClusterHealth(clusterKey, status, numOsds, numOsdsUp, numOsdsIn, numPgs, numMons, quorumSize,
                System.currentTimeMillis(), null);
    }

    public boolean isReachable() {
        return error == null && overallStatus != null;
    }

    public boolean isHealthy(Set<String> acceptedStates) {
        return isReachable() && acceptedStates.contains(overallStatus);
    }

    public boolean hasOsdDegradation() {
        return numOsds > 0 && (numOsdsUp < numOsds || numOsdsIn < numOsds);
    }

    public String getClusterKey() {
        return clusterKey;
    }

    public String getOverallStatus() {
        return overallStatus;
    }

    public int getNumOsds() {
        return numOsds;
    }

    public int getNumOsdsUp() {
        return numOsdsUp;
    }

    public int getNumOsdsIn() {
        return numOsdsIn;
    }

    public int getNumPgs() {
        return numPgs;
    }

    public int getNumMons() {
        return numMons;
    }

    public int getQuorumSize() {
        return quorumSize;
    }

    public long getLastChecked() {
        return lastChecked;
    }

    public String getError() {
        return error;
    }

    @Override
    public String toString() {
        if (!isReachable()) {
            return String.format("CephClusterHealth[cluster=%s, unreachable: %s]", clusterKey, error);
        }
        return String.format("CephClusterHealth[cluster=%s, status=%s, osds=%d up=%d in=%d, pgs=%d, mons=%d quorum=%d]",
                clusterKey, overallStatus, numOsds, numOsdsUp, numOsdsIn, numPgs, numMons, quorumSize);
    }
}
