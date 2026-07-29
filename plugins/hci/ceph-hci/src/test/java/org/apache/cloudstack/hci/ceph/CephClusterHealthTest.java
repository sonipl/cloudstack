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

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.Set;

import org.junit.Test;

public class CephClusterHealthTest {

    private static final String LEGACY_STATUS_JSON = "{"
            + "\"health\": {\"status\": \"HEALTH_OK\", \"checks\": {}},"
            + "\"osdmap\": {\"osdmap\": {\"num_osds\": 6, \"num_up_osds\": 6, \"num_in_osds\": 6}},"
            + "\"pgmap\": {\"num_pgs\": 129},"
            + "\"monmap\": {\"num_mons\": 3},"
            + "\"quorum\": [0, 1, 2]"
            + "}";

    private static final String MODERN_STATUS_JSON_DEGRADED = "{"
            + "\"health\": {\"overall_status\": \"HEALTH_WARN\"},"
            + "\"osdmap\": {\"osdmap\": {\"num_osds\": 6, \"num_up_osds\": 5, \"num_in_osds\": 6}},"
            + "\"pgmap\": {\"num_pgs\": 129},"
            + "\"monmap\": {\"num_mons\": 3},"
            + "\"quorum\": [0, 1, 2]"
            + "}";

    private static final String ERROR_STATUS_JSON = "{"
            + "\"health\": {\"status\": \"HEALTH_ERR\"},"
            + "\"osdmap\": {\"osdmap\": {\"num_osds\": 6, \"num_up_osds\": 4, \"num_in_osds\": 4}},"
            + "\"pgmap\": {\"num_pgs\": 129},"
            + "\"monmap\": {\"num_mons\": 3},"
            + "\"quorum\": [0]"
            + "}";

    @Test
    public void testParseLegacyHealthStatusJson() {
        CephClusterHealth health = CephClusterHealth.fromStatusJson("10.0.0.1:3300", LEGACY_STATUS_JSON);
        assertTrue(health.isReachable());
        assertEquals("HEALTH_OK", health.getOverallStatus());
        assertEquals(6, health.getNumOsds());
        assertEquals(6, health.getNumOsdsUp());
        assertEquals(6, health.getNumOsdsIn());
        assertEquals(129, health.getNumPgs());
        assertEquals(3, health.getNumMons());
        assertEquals(3, health.getQuorumSize());
        assertFalse(health.hasOsdDegradation());
    }

    @Test
    public void testParseModernOverallStatusJsonWithDegradedOsd() {
        CephClusterHealth health = CephClusterHealth.fromStatusJson("10.0.0.1:3300", MODERN_STATUS_JSON_DEGRADED);
        assertTrue(health.isReachable());
        assertEquals("HEALTH_WARN", health.getOverallStatus());
        assertEquals(5, health.getNumOsdsUp());
        assertTrue(health.hasOsdDegradation());
    }

    @Test
    public void testIsHealthyWithAcceptedStates() {
        CephClusterHealth ok = CephClusterHealth.fromStatusJson("c1", LEGACY_STATUS_JSON);
        CephClusterHealth warn = CephClusterHealth.fromStatusJson("c1", MODERN_STATUS_JSON_DEGRADED);
        CephClusterHealth err = CephClusterHealth.fromStatusJson("c1", ERROR_STATUS_JSON);

        Set<String> accepted = Set.of(CephClusterHealth.HEALTH_OK, CephClusterHealth.HEALTH_WARN);
        assertTrue(ok.isHealthy(accepted));
        assertTrue(warn.isHealthy(accepted));
        assertFalse(err.isHealthy(accepted));

        Set<String> strict = Set.of(CephClusterHealth.HEALTH_OK);
        assertTrue(ok.isHealthy(strict));
        assertFalse(warn.isHealthy(strict));
    }

    @Test
    public void testErrorHealthIsNotReachableAndNotHealthy() {
        CephClusterHealth health = CephClusterHealth.error("c1", "ssh timeout");
        assertFalse(health.isReachable());
        assertFalse(health.isHealthy(Set.of(CephClusterHealth.HEALTH_OK)));
        assertEquals("ssh timeout", health.getError());
        assertNull(health.getOverallStatus());
    }
}
