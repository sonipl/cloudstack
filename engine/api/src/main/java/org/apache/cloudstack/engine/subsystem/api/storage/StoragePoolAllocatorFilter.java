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
package org.apache.cloudstack.engine.subsystem.api.storage;

import com.cloud.deploy.DeploymentPlan;
import com.cloud.storage.StoragePool;
import com.cloud.vm.DiskProfile;

/**
 * Optional predicate consulted by {@link StoragePoolAllocator} implementations
 * (via {@code AbstractStoragePoolAllocator#filter}) before a pool is accepted
 * for new volume/VM placement. Plugins may register beans of this type to gate
 * allocation (for example Ceph HCI health) without replacing ClusterScope /
 * ZoneWide allocators.
 * <p>
 * Filters that do not apply to a given pool must return {@code true}.
 */
public interface StoragePoolAllocatorFilter {

    /**
     * @return false to exclude the pool from allocation; true to allow it
     *         (or when the filter does not apply).
     */
    boolean isStoragePoolAcceptable(StoragePool pool, DiskProfile diskProfile, DeploymentPlan plan);
}
