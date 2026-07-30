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

package org.apache.cloudstack.hci.ceph.allocator;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import org.apache.cloudstack.hci.ceph.CephHciManager;
import org.junit.Before;
import org.junit.Test;

import com.cloud.deploy.DeploymentPlan;
import com.cloud.storage.StoragePool;
import com.cloud.vm.DiskProfile;

public class CephHciStoragePoolAllocatorFilterTest {

    private CephHciManager cephHciManager;
    private CephHciStoragePoolAllocatorFilter filter;
    private StoragePool pool;
    private DiskProfile diskProfile;
    private DeploymentPlan plan;

    @Before
    public void setUp() {
        cephHciManager = mock(CephHciManager.class);
        filter = new CephHciStoragePoolAllocatorFilter();
        filter.cephHciManager = cephHciManager;
        pool = mock(StoragePool.class);
        diskProfile = mock(DiskProfile.class);
        plan = mock(DeploymentPlan.class);
    }

    @Test
    public void testAcceptableWhenManagerAllows() {
        when(cephHciManager.isPoolAllocationAllowed(pool)).thenReturn(true);
        assertTrue(filter.isStoragePoolAcceptable(pool, diskProfile, plan));
    }

    @Test
    public void testRejectedWhenManagerDenies() {
        when(cephHciManager.isPoolAllocationAllowed(pool)).thenReturn(false);
        assertFalse(filter.isStoragePoolAcceptable(pool, diskProfile, plan));
    }
}
