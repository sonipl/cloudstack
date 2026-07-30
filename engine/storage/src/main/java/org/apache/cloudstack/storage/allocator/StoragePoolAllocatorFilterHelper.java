// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.
package org.apache.cloudstack.storage.allocator;

import java.util.Collections;
import java.util.List;

import org.apache.cloudstack.engine.subsystem.api.storage.StoragePoolAllocatorFilter;
import org.apache.commons.collections.CollectionUtils;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import com.cloud.deploy.DeploymentPlan;
import com.cloud.storage.StoragePool;
import com.cloud.vm.DiskProfile;

/**
 * Holds the live list of {@link StoragePoolAllocatorFilter} beans registered
 * via the storage-pool allocator filter ExtensionRegistry, and evaluates them
 * for every pool considered by {@link AbstractStoragePoolAllocator#filter}.
 */
public class StoragePoolAllocatorFilterHelper {

    protected final Logger logger = LogManager.getLogger(getClass());

    private List<StoragePoolAllocatorFilter> filters = Collections.emptyList();

    public void setFilters(List<StoragePoolAllocatorFilter> filters) {
        this.filters = filters != null ? filters : Collections.emptyList();
    }

    public List<StoragePoolAllocatorFilter> getFilters() {
        return filters;
    }

    public boolean isPoolAcceptable(StoragePool pool, DiskProfile diskProfile, DeploymentPlan plan) {
        if (CollectionUtils.isEmpty(filters)) {
            return true;
        }
        for (StoragePoolAllocatorFilter filter : filters) {
            if (!filter.isStoragePoolAcceptable(pool, diskProfile, plan)) {
                logger.debug("Storage pool [{}] rejected by allocator filter [{}].", pool, filter.getClass().getSimpleName());
                return false;
            }
        }
        return true;
    }
}
