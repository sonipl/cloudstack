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

package org.apache.cloudstack.hci.ceph.api.response;

import java.util.Date;

import org.apache.cloudstack.api.response.BaseResponse;

import com.cloud.serializer.Param;
import com.google.gson.annotations.SerializedName;

public class HciCephHealthResponse extends BaseResponse {

    @SerializedName("storagepoolid")
    @Param(description = "the UUID of the primary storage pool backed by Ceph RBD")
    private String storagePoolId;

    @SerializedName("storagepoolname")
    @Param(description = "the name of the primary storage pool")
    private String storagePoolName;

    @SerializedName("zoneid")
    @Param(description = "the UUID of the zone of the storage pool")
    private String zoneId;

    @SerializedName("clusterid")
    @Param(description = "the UUID of the cluster of the storage pool, if cluster scoped")
    private String clusterId;

    @SerializedName("cephcluster")
    @Param(description = "the Ceph monitor endpoint identifying the backing Ceph cluster")
    private String cephCluster;

    @SerializedName("healthstatus")
    @Param(description = "overall Ceph cluster health status (HEALTH_OK, HEALTH_WARN, HEALTH_ERR)")
    private String healthStatus;

    @SerializedName("allocationallowed")
    @Param(description = "whether new VM/volume allocations are currently allowed on this pool based on Ceph health")
    private Boolean allocationAllowed;

    @SerializedName("osdstotal")
    @Param(description = "total number of OSDs in the Ceph cluster")
    private Integer osdsTotal;

    @SerializedName("osdsup")
    @Param(description = "number of OSDs currently up in the Ceph cluster")
    private Integer osdsUp;

    @SerializedName("osdsin")
    @Param(description = "number of OSDs currently in the Ceph cluster")
    private Integer osdsIn;

    @SerializedName("placementgroups")
    @Param(description = "number of placement groups in the Ceph cluster")
    private Integer placementGroups;

    @SerializedName("monitors")
    @Param(description = "number of monitors in the Ceph cluster")
    private Integer monitors;

    @SerializedName("quorumsize")
    @Param(description = "current Ceph monitor quorum size")
    private Integer quorumSize;

    @SerializedName("osddegraded")
    @Param(description = "true when one or more OSDs are down or out, analogous to a vSAN degraded object state")
    private Boolean osdDegraded;

    @SerializedName("lastchecked")
    @Param(description = "the time this health data was last collected")
    private Date lastChecked;

    @SerializedName("error")
    @Param(description = "error encountered while collecting Ceph health, if any")
    private String error;

    public void setStoragePoolId(String storagePoolId) {
        this.storagePoolId = storagePoolId;
    }

    public void setStoragePoolName(String storagePoolName) {
        this.storagePoolName = storagePoolName;
    }

    public void setZoneId(String zoneId) {
        this.zoneId = zoneId;
    }

    public void setClusterId(String clusterId) {
        this.clusterId = clusterId;
    }

    public void setCephCluster(String cephCluster) {
        this.cephCluster = cephCluster;
    }

    public void setHealthStatus(String healthStatus) {
        this.healthStatus = healthStatus;
    }

    public void setAllocationAllowed(Boolean allocationAllowed) {
        this.allocationAllowed = allocationAllowed;
    }

    public void setOsdsTotal(Integer osdsTotal) {
        this.osdsTotal = osdsTotal;
    }

    public void setOsdsUp(Integer osdsUp) {
        this.osdsUp = osdsUp;
    }

    public void setOsdsIn(Integer osdsIn) {
        this.osdsIn = osdsIn;
    }

    public void setPlacementGroups(Integer placementGroups) {
        this.placementGroups = placementGroups;
    }

    public void setMonitors(Integer monitors) {
        this.monitors = monitors;
    }

    public void setQuorumSize(Integer quorumSize) {
        this.quorumSize = quorumSize;
    }

    public void setOsdDegraded(Boolean osdDegraded) {
        this.osdDegraded = osdDegraded;
    }

    public void setLastChecked(Date lastChecked) {
        this.lastChecked = lastChecked;
    }

    public void setError(String error) {
        this.error = error;
    }
}
