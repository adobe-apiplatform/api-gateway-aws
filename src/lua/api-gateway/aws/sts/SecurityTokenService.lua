local AwsService = require"api-gateway.aws.AwsService"
local cjson = require"cjson"
local error = error

local _M = AwsService:new({ ___super = true })
local super = {
    instance = _M,
    constructor = _M.constructor
}

function _M.new(self, o)
    ngx.log(ngx.DEBUG, "StsService() o=", tostring(o))
    local o = o or {}
    o.aws_service = "sts"
    -- aws_service_name is used in the X-Amz-Target Header: i.e Kinesis_20131202.ListStreams
    o.aws_service_name = "STS_20110615"

    super.constructor(_M, o)

    setmetatable(o, self)
    self.__index = self
    return o
end

---
-- @param roleARN
-- @param roleSessionName
-- @param policy
-- @param durationSeconds
-- @param externalId
--
function _M:assumeRole(roleARN, roleSessionName, policy, durationSeconds, externalId)
    assert(roleARN ~= nil, "Please provide a valid roleARN." )
    assert(roleSessionName ~= nil, "Please provide a valid roleSessionName." )
    local arguments = {
        RoleArn = roleARN,
        RoleSessionName = roleSessionName,
        Policy = policy,
        DurationSeconds = durationSeconds or 3600,
        ExternalId = externalId
    }
    local ok, code, headers, status, body = self:performAction("AssumeRole", arguments, "/", "POST", true)

    if (code == ngx.HTTP_OK and body ~= nil) then
        return cjson.decode(body), code, headers, status, body
    end
    return nil, code, headers, status, body
end

return _M