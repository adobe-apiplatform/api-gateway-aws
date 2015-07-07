-- Kinesis Client


local AwsService = require"api-gateway.aws.AwsService"
local cjson = require"cjson"
local error = error

local _M = AwsService:new({ ___super = true })
local super = {
    instance = _M,
    constructor = _M.constructor
}

function _M.new(self, o)
    ngx.log(ngx.DEBUG, "KinesisService() o=", tostring(o))
    local o = o or {}
    o.aws_service = "kinesis"
    -- aws_service_name is used in the X-Amz-Target Header: i.e Kinesis_20131202.ListStreams
    o.aws_service_name = "Kinesis_20131202"

    super.constructor(_M, o)

    setmetatable(o, self)
    self.__index = self
    return o
end

-- API: http://docs.aws.amazon.com/kinesis/latest/APIReference/API_CreateStream.html
-- {
--    "ShardCount": number,
--    "StreamName": "string"
-- }
function _M:createStream(streamName, shardCount)
    assert(streamName ~= nil, "Please provide a valid streamName." )
    local arguments = {
        StreamName = streamName,
        ShardCount = shardCount or 1
    }
    local ok, code, headers, status, body = self:performAction("CreateStream", arguments, "/", "POST", true)

    if (code == ngx.HTTP_OK and body ~= nil) then
        return {}, code, headers, status, body
    end
    return nil, code, headers, status, body
end

-- API: http://docs.aws.amazon.com/kinesis/latest/APIReference/API_DeleteStream.html
-- {
--    "StreamName": "string"
-- }
function _M:deleteStream(streamName)
    assert(streamName ~= nil, "Please provide a valid streamName." )
    local arguments = {
        StreamName = streamName,
    }
    local ok, code, headers, status, body = self:performAction("DeleteStream", arguments, "/", "POST", true)

    if (code == ngx.HTTP_OK and body ~= nil) then
        return {}, code, headers, status, body
    end
    return nil, code, headers, status, body
end



-- API: http://docs.aws.amazon.com/kinesis/latest/APIReference/API_ListStreams.html
-- {
--    "ExclusiveStartStreamName": "string",
--    "Limit": number
-- }
function _M:listStreams(streamName, limit)
    local arguments = {
        ExclusiveStartStreamName = streamName,
        Limit = limit
    }
    local ok, code, headers, status, body = self:performAction("ListStreams", arguments, "/", "POST", true)

    if (code == ngx.HTTP_OK and body ~= nil) then
        return cjson.decode(body), code, headers, status, body
    end
    return nil, code, headers, status, body
end




return _M

