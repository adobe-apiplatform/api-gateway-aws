-- SNS Client
-- Created by IntelliJ IDEA.
-- User: ddascal
-- Date: 21/11/14
-- Time: 16:16
-- To change this template use File | Settings | File Templates.


local AwsService = require"api-gateway.aws.AwsService"
local cjson = require"cjson"
local error = error

local _M = AwsService:new({ ___super = true })

function _M:new(o)
    local o = o or {}
    o.aws_service = "sns"
    setmetatable(o, self)
    self.__index = self
    return o
end

-- API: http://docs.aws.amazon.com/sns/latest/APIReference/API_ListTopics.html
function _M:listTopics()
    local arguments = {}
    local ok, code, headers, status, body = self:performAction("ListTopics", arguments, "/", "GET", true)

    if (code == ngx.HTTP_OK and body ~= nil) then
        return cjson.decode(body), status, body
    end
    return nil, status, body
end

-- API: http://docs.aws.amazon.com/sns/latest/APIReference/API_Publish.html

function _M:publish(subject, message, topicArn, targetArn)
    local arguments = {
        Message = message,
        Subject = subject,
        TargetArn = targetArn,
        TopicArn = topicArn
    }
    local ok, code, headers, status, body = self:performAction("Publish", arguments, "/", "GET", true)

    if (code == ngx.HTTP_OK and body ~= nil) then
        return cjson.decode(body), status, body
    end
    return nil, status, body
end

return _M

