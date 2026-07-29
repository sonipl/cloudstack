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

import javax.inject.Inject;

import org.apache.cloudstack.acl.RoleType;
import org.apache.cloudstack.api.APICommand;
import org.apache.cloudstack.api.BaseCmd;
import org.apache.cloudstack.api.ResponseObject;
import org.apache.cloudstack.api.response.SuccessResponse;
import org.apache.cloudstack.hci.ceph.CephHciManager;

@APICommand(name = RefreshHciCephHealthCmd.APINAME, description = "Forces a refresh of the cached Ceph cluster health used for HCI storage placement",
        responseObject = SuccessResponse.class, responseView = ResponseObject.ResponseView.Full,
        requestHasSensitiveInfo = false, responseHasSensitiveInfo = false, since = "4.23.0",
        authorized = {RoleType.Admin})
public class RefreshHciCephHealthCmd extends BaseCmd {

    public static final String APINAME = "refreshHciCephHealth";

    @Inject
    private CephHciManager cephHciManager;

    @Override
    public void execute() {
        cephHciManager.refreshHealth();
        SuccessResponse response = new SuccessResponse(getCommandName());
        setResponseObject(response);
    }

    @Override
    public long getEntityOwnerId() {
        return 0;
    }
}
