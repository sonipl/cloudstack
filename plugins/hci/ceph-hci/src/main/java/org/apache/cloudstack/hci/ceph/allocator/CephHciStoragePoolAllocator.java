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

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import javax.inject.Inject;

import org.apache.cloudstack.hci.ceph.CephHciManager;
import org.apache.cloudstack.storage.allocator.AbstractStoragePoolAllocator;
import org.apache.cloudstack.storage.datastore.db.StoragePoolVO;

import com.cloud.deploy.DeploymentPlan;
import com.cloud.deploy.DeploymentPlanner.ExcludeList;
import com.cloud.storage.ScopeType;
import com.cloud.storage.StoragePool;
import com.cloud.vm.DiskProfile;
import com.cloud.vm.VirtualMachineProfile;

/**
 * Storage pool allocator with vSAN-like data service awareness: besides the
 * standard capacity/tag/scope checks it excludes RBD pools whose backing
 * Ceph cluster is currently unhealthy (as tracked by {@link CephHciManager}),
 * preventing new VM/volume placement on degraded hyperconverged storage.
 */
public class CephHciStoragePoolAllocator extends AbstractStoragePoolAllocator {

    @Inject
    protected CephHciManager cephHciManager;

    @Override
    public List<StoragePool> select(DiskProfile dskCh, VirtualMachineProfile vmProfile, DeploymentPlan plan,
            ExcludeList avoid, int returnUpTo, boolean bypassStorageTypeCheck, String keyword) {
        logStartOfSearch(dskCh, vmProfile, plan, returnUpTo, bypassStorageTypeCheck);

        List<StoragePool> suitablePools = new ArrayList<>();

        long dcId = plan.getDataCenterId();
        Long podId = plan.getPodId();
        Long clusterId = plan.getClusterId();

        List<StoragePoolVO> pools = new ArrayList<>();
        if (podId != null && clusterId != null) {
            pools.addAll(storagePoolDao.listBy(dcId, podId, clusterId, ScopeType.CLUSTER));
        }
        pools.addAll(storagePoolDao.findZoneWideStoragePoolsByTags(dcId, dskCh.getTags(), true));

        if (pools.isEmpty()) {
            logger.debug("CephHciStoragePoolAllocator found no pools in dc [{}], pod [{}], cluster [{}].", dcId, podId, clusterId);
            return suitablePools;
        }

        Collections.shuffle(pools);

        for (StoragePoolVO pool : pools) {
            if (suitablePools.size() == returnUpTo) {
                break;
            }
            StoragePool storagePool = (StoragePool)this.dataStoreMgr.getPrimaryDataStore(pool.getId());
            if (!cephHciManager.isPoolAllocationAllowed(storagePool)) {
                logger.debug("Skipping pool [{}], its backing Ceph cluster is not in an accepted health state.", pool);
                avoid.addPool(pool.getId());
                continue;
            }
            if (filter(avoid, storagePool, dskCh, plan)) {
                logger.trace("Found suitable storage pool [{}], adding to list.", pool);
                suitablePools.add(storagePool);
            }
        }

        logEndOfSearch(suitablePools);

        return suitablePools;
    }
}
