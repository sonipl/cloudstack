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

package org.apache.cloudstack.hci.ceph.api;

import java.util.List;

import javax.inject.Inject;

import org.apache.cloudstack.acl.RoleType;
import org.apache.cloudstack.api.APICommand;
import org.apache.cloudstack.api.ApiConstants;
import org.apache.cloudstack.api.BaseListCmd;
import org.apache.cloudstack.api.Parameter;
import org.apache.cloudstack.api.ResponseObject;
import org.apache.cloudstack.api.response.ListResponse;
import org.apache.cloudstack.hci.ceph.CephHciManager;
import org.apache.cloudstack.hci.ceph.api.response.HciCephHealthResponse;

@APICommand(name = ListHciCephHealthCmd.APINAME, description = "Lists Ceph cluster health for HCI (hyperconverged) RBD primary storage pools",
        responseObject = HciCephHealthResponse.class, responseView = ResponseObject.ResponseView.Full,
        requestHasSensitiveInfo = false, responseHasSensitiveInfo = false, since = "4.23.0",
        authorized = {RoleType.Admin})
public class ListHciCephHealthCmd extends BaseListCmd {

    public static final String APINAME = "listHciCephHealth";

    @Inject
    private CephHciManager cephHciManager;

    @Parameter(name = ApiConstants.ZONE_ID, type = CommandType.UUID, entityType = org.apache.cloudstack.api.response.ZoneResponse.class,
            description = "the UUID of the zone to list Ceph HCI health for")
    private Long zoneId;

    public Long getZoneId() {
        return zoneId;
    }

    @Override
    public void execute() {
        List<HciCephHealthResponse> healthResponses = cephHciManager.listHealth(getZoneId());
        ListResponse<HciCephHealthResponse> response = new ListResponse<>();
        response.setResponses(healthResponses, healthResponses.size());
        response.setResponseName(getCommandName());
        setResponseObject(response);
    }
}
