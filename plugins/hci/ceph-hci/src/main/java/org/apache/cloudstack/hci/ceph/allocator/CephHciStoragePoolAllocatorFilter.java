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

import javax.inject.Inject;

import org.apache.cloudstack.engine.subsystem.api.storage.StoragePoolAllocatorFilter;
import org.apache.cloudstack.hci.ceph.CephHciManager;

import com.cloud.deploy.DeploymentPlan;
import com.cloud.storage.StoragePool;
import com.cloud.vm.DiskProfile;

/**
 * Gates ClusterScope / ZoneWide / Local allocation through the shared
 * StoragePoolAllocator filter hook so unhealthy Ceph-backed RBD pools are
 * excluded without replacing the stock allocators.
 */
public class CephHciStoragePoolAllocatorFilter implements StoragePoolAllocatorFilter {

    @Inject
    protected CephHciManager cephHciManager;

    @Override
    public boolean isStoragePoolAcceptable(StoragePool pool, DiskProfile diskProfile, DeploymentPlan plan) {
        return cephHciManager.isPoolAllocationAllowed(pool);
    }
}
