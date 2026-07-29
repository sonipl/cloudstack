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

package org.apache.cloudstack.hci.ceph.allocator;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.util.List;

import org.apache.cloudstack.engine.subsystem.api.storage.DataStoreManager;
import org.apache.cloudstack.hci.ceph.CephHciManager;
import org.apache.cloudstack.storage.datastore.db.PrimaryDataStoreDao;
import org.apache.cloudstack.storage.datastore.db.StoragePoolVO;
import org.junit.Before;
import org.junit.Test;

import com.cloud.deploy.DeploymentPlan;
import com.cloud.deploy.DeploymentPlanner.ExcludeList;
import com.cloud.storage.ScopeType;
import com.cloud.storage.StoragePool;
import com.cloud.vm.DiskProfile;
import com.cloud.vm.VirtualMachineProfile;

public class CephHciStoragePoolAllocatorTest {

    private PrimaryDataStoreDao storagePoolDao;
    private DataStoreManager dataStoreMgr;
    private CephHciManager cephHciManager;
    private TestableAllocator allocator;

    private DiskProfile diskProfile;
    private VirtualMachineProfile vmProfile;
    private DeploymentPlan plan;

    /**
     * Bypasses the capacity/tag checks of the abstract parent so the test
     * focuses on Ceph health gating only.
     */
    static class TestableAllocator extends CephHciStoragePoolAllocator {
        void setStoragePoolDao(PrimaryDataStoreDao dao) {
            this.storagePoolDao = dao;
        }

        void setDataStoreMgr(DataStoreManager mgr) {
            this.dataStoreMgr = mgr;
        }

        void setCephHciManager(CephHciManager mgr) {
            this.cephHciManager = mgr;
        }

        @Override
        protected boolean filter(ExcludeList avoid, StoragePool pool, DiskProfile dskCh, DeploymentPlan plan) {
            return true;
        }
    }

    @Before
    public void setUp() {
        storagePoolDao = mock(PrimaryDataStoreDao.class);
        dataStoreMgr = mock(DataStoreManager.class);
        cephHciManager = mock(CephHciManager.class);

        allocator = new TestableAllocator();
        allocator.setStoragePoolDao(storagePoolDao);
        allocator.setDataStoreMgr(dataStoreMgr);
        allocator.setCephHciManager(cephHciManager);

        diskProfile = mock(DiskProfile.class);
        when(diskProfile.getTags()).thenReturn(new String[0]);
        vmProfile = mock(VirtualMachineProfile.class);
        plan = mock(DeploymentPlan.class);
        when(plan.getDataCenterId()).thenReturn(1L);
        when(plan.getPodId()).thenReturn(1L);
        when(plan.getClusterId()).thenReturn(1L);
    }

    private StoragePoolVO mockPoolVO(long id, String name) {
        StoragePoolVO pool = mock(StoragePoolVO.class);
        when(pool.getId()).thenReturn(id);
        when(pool.getName()).thenReturn(name);
        return pool;
    }

    private StoragePool mockPool(long id, String name) {
        StoragePool pool = mock(StoragePool.class);
        when(pool.getId()).thenReturn(id);
        when(pool.getName()).thenReturn(name);
        return pool;
    }

    @Test
    public void testUnhealthyCephPoolIsExcludedAndAddedToAvoidList() {
        StoragePoolVO unhealthyVO = mockPoolVO(10L, "rbd-pool-unhealthy");
        StoragePool unhealthy = mockPool(10L, "rbd-pool-unhealthy");

        when(storagePoolDao.listBy(eq(1L), eq(1L), eq(1L), eq(ScopeType.CLUSTER))).thenReturn(List.of(unhealthyVO));
        when(storagePoolDao.findZoneWideStoragePoolsByTags(anyLong(), any(), anyBoolean())).thenReturn(List.of());
        when(dataStoreMgr.getPrimaryDataStore(10L)).thenReturn(unhealthy);
        when(cephHciManager.isPoolAllocationAllowed(unhealthy)).thenReturn(false);

        ExcludeList avoid = new ExcludeList();
        List<StoragePool> result = allocator.select(diskProfile, vmProfile, plan, avoid, 1, false, null);

        assertTrue(result.isEmpty());
        assertTrue(avoid.getPoolsToAvoid().contains(10L));
    }

    @Test
    public void testHealthyCephPoolIsSuitable() {
        StoragePoolVO healthyVO = mockPoolVO(11L, "rbd-pool-healthy");
        StoragePool healthy = mockPool(11L, "rbd-pool-healthy");

        when(storagePoolDao.listBy(eq(1L), eq(1L), eq(1L), eq(ScopeType.CLUSTER))).thenReturn(List.of(healthyVO));
        when(storagePoolDao.findZoneWideStoragePoolsByTags(anyLong(), any(), anyBoolean())).thenReturn(List.of());
        when(dataStoreMgr.getPrimaryDataStore(11L)).thenReturn(healthy);
        when(cephHciManager.isPoolAllocationAllowed(healthy)).thenReturn(true);

        ExcludeList avoid = new ExcludeList();
        List<StoragePool> result = allocator.select(diskProfile, vmProfile, plan, avoid, 1, false, null);

        assertEquals(1, result.size());
        assertEquals(11L, result.get(0).getId());
    }

    @Test
    public void testZoneWideRbdPoolsAreAlsoConsidered() {
        StoragePoolVO zoneWideVO = mockPoolVO(12L, "rbd-pool-zonewide");
        StoragePool zoneWide = mockPool(12L, "rbd-pool-zonewide");

        when(storagePoolDao.listBy(anyLong(), anyLong(), anyLong(), eq(ScopeType.CLUSTER))).thenReturn(List.of());
        when(storagePoolDao.findZoneWideStoragePoolsByTags(eq(1L), any(), eq(true))).thenReturn(List.of(zoneWideVO));
        when(dataStoreMgr.getPrimaryDataStore(12L)).thenReturn(zoneWide);
        when(cephHciManager.isPoolAllocationAllowed(zoneWide)).thenReturn(true);

        ExcludeList avoid = new ExcludeList();
        List<StoragePool> result = allocator.select(diskProfile, vmProfile, plan, avoid, 1, false, null);

        assertEquals(1, result.size());
        assertEquals(12L, result.get(0).getId());
    }

    @Test
    public void testNoPoolsReturnsEmptyList() {
        when(storagePoolDao.listBy(anyLong(), anyLong(), anyLong(), any())).thenReturn(List.of());
        when(storagePoolDao.findZoneWideStoragePoolsByTags(anyLong(), any(), anyBoolean())).thenReturn(List.of());

        ExcludeList avoid = new ExcludeList();
        List<StoragePool> result = allocator.select(diskProfile, vmProfile, plan, avoid, 1, false, null);

        assertTrue(result.isEmpty());
    }
}
