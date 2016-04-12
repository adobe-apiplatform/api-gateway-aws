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
    o.aws_service_name = "AWSSecurityTokenServiceV20110615"

    super.constructor(_M, o)

    setmetatable(o, self)
    self.__index = self
    return o
end

--- @see http://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html
-- @param roleARN The Amazon Resource Name (ARN) of the role to assume. Type: String
--          Length Constraints: Minimum length of 20. Maximum length of 2048.
--          Required
-- @param roleSessionName An identifier for the assumed role session.
--          Use it when the same role is assumed by different principals or for different reasons/policy.
--          Required
-- @param policy  An IAM policy in JSON format.
-- @param durationSeconds The duration, in seconds, of the role session.
--          Valid Range: Minimum value of 900. Maximum value of 3600.
-- @param externalId A unique identifier used by third parties
--
function _M:assumeRole(roleARN, roleSessionName, policy, durationSeconds, externalId)
    assert(roleARN ~= nil, "Please provide a valid roleARN." )
    assert(roleSessionName ~= nil, "Please provide a valid roleSessionName." )
    local arguments = {
        Version="2011-06-15",
        RoleArn = roleARN,
        RoleSessionName = roleSessionName,
        Policy = policy,
        DurationSeconds = durationSeconds or 3600,
        ExternalId = externalId
    }
    local ok, code, headers, status, body = self:performAction("AssumeRole", arguments, "/", "POST", true, 30000, "application/x-www-form-urlencoded")

    if (code == ngx.HTTP_OK and body ~= nil) then
        return cjson.decode(body), code, headers, status, body
    end
    return nil, code, headers, status, body
end

return _M