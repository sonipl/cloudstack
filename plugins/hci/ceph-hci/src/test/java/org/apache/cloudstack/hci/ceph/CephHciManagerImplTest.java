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

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Set;

import org.junit.Test;

import com.cloud.storage.Storage.StoragePoolType;
import com.cloud.storage.StoragePool;

public class CephHciManagerImplTest {

    @Test
    public void testParseMonitorHostsCommaSeparatedAndSorts() {
        List<String> hosts = CephHciManagerImpl.parseMonitorHosts("10.0.0.3,10.0.0.1,10.0.0.2");
        assertEquals(List.of("10.0.0.1", "10.0.0.2", "10.0.0.3"), hosts);
    }

    @Test
    public void testParseMonitorHostsStripsPortsAndDedupes() {
        List<String> hosts = CephHciManagerImpl.parseMonitorHosts("10.0.0.1:6789;10.0.0.1:3300 10.0.0.2");
        assertEquals(List.of("10.0.0.1", "10.0.0.2"), hosts);
    }

    @Test
    public void testClusterKeyStableRegardlessOfMonOrder() {
        StoragePool a = mock(StoragePool.class);
        when(a.getHostAddress()).thenReturn("10.0.0.2,10.0.0.1");
        when(a.getPort()).thenReturn(6789);

        StoragePool b = mock(StoragePool.class);
        when(b.getHostAddress()).thenReturn("10.0.0.1,10.0.0.2");
        when(b.getPort()).thenReturn(6789);

        assertEquals(CephHciManagerImpl.clusterKeyFor(a), CephHciManagerImpl.clusterKeyFor(b));
        assertEquals("10.0.0.1,10.0.0.2:6789", CephHciManagerImpl.clusterKeyFor(a));
    }

    @Test
    public void testAcceptedHealthStatesTrimWhitespace() {
        // Mirrors CephHciManagerImpl.acceptedHealthStates() tokenisation
        // (ConfigKey.value() needs a running management server).
        Set<String> parsed = java.util.Arrays.stream("HEALTH_OK, HEALTH_WARN , ".split(","))
                .map(String::trim)
                .filter(s -> !s.isBlank())
                .collect(java.util.stream.Collectors.toSet());
        assertTrue(parsed.contains("HEALTH_OK"));
        assertTrue(parsed.contains("HEALTH_WARN"));
        assertEquals(2, parsed.size());
        assertFalse(parsed.contains(" HEALTH_WARN "));
    }

    @Test
    public void testIsPoolAllocationAllowedForNonRbd() {
        CephHciManagerImpl mgr = new CephHciManagerImpl();
        StoragePool pool = mock(StoragePool.class);
        when(pool.getPoolType()).thenReturn(StoragePoolType.NetworkFilesystem);
        assertTrue(mgr.isPoolAllocationAllowed(pool));
    }

    @Test
    public void testFromStatusJsonWithSshBannerPrefix() {
        String output = "Last login: Mon Jan 1\n{\"health\":{\"status\":\"HEALTH_OK\"},\"osdmap\":{\"osdmap\":{\"num_osds\":3,\"num_up_osds\":3,\"num_in_osds\":3}},\"pgmap\":{\"num_pgs\":32},\"monmap\":{\"num_mons\":3},\"quorum\":[0,1,2]}";
        CephClusterHealth health = CephClusterHealth.fromStatusJson("c1", output);
        assertTrue(health.isReachable());
        assertEquals("HEALTH_OK", health.getOverallStatus());
    }
}
