--- Base Class for working with AWS Services.
--  It's responsible for making API Requests to most of the AWS Services
--
-- Created by IntelliJ IDEA.
-- User: ddascal
-- Date: 24/11/14
-- Time: 18:46
--

local _M = { _VERSION = '0.01' }

local setmetatable = setmetatable
local error = error
local debug_mode = ngx.config.debug
local http = require "api-gateway.aws.httpclient.http"
local AWSV4S = require "api-gateway.aws.AwsV4Signature"
local cjson = require"cjson"

local http_client = http:new()

---
-- @param o object containing info about the AWS Service and Credentials or IAM User to use
--     o.aws_region      - AWS Region
--     o.aws_service     - the AWS Service to call
--     o.aws_secret_key  - AWS Credential
--     o.aws_access_key  - AWS Credential
--     o.aws_iam_user    - required if aws_secret_key,aws_access_key pair is missing
--
-- NOTE: class inheirtance inspired from: http://www.lua.org/pil/16.2.html
function _M:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    if not o.___super then
        self:throwIfInitParamsInvalid(o)
    end
    return o
end

function _M:throwIfInitParamsInvalid(o)
    if (o == nil ) then
        error("Could not initialize. Missing init object. Please configure the AWS Service properly.")
    end

    local iam_user = o.aws_iam_user or ""
    local secret_key = o.aws_secret_key or ""
    local access_key = o.aws_access_key or ""


    if iam_user == "" and secret_key == "" and access_key == "" then
        local s = ""
        for k,v in pairs(o) do
            s = s .. ", " .. k .. "=" .. v
        end
        error("Invalid credentials. At least aws_iam_user or (aws_secret_key,aws_access_key) need to be provided. Object is:" .. s)
    end

    local service = o.aws_service or ""
    if service == "" then
        error("aws_service is missing. Please provide one.")
    end

    local region = o.aws_region or ""
    if region == "" then
        error("aws_region is missing. Please provide one.")
    end
end

function _M:debug(...)
    if debug_mode then
        ngx.log(ngx.DEBUG, "AwsService: ", ...)
    end
end

function _M:getHttpClient()
    return http_client
end

function _M:getAWSHost()
    return self.aws_service .."." .. self.aws_region .. ".amazonaws.com"
end

function _M:getAuthorizationHeader( http_method, path, uri_args, body )
    local awsAuth =  AWSV4S:new({
                       aws_region  = self.aws_region,
                       aws_service = self.aws_service,
                       aws_secret_key = self.aws_secret_key,
                       aws_access_key = self.aws_access_key
                  })
    local authorization = awsAuth:getAuthorizationHeader( http_method,
                                                        path, -- "/"
                                                        uri_args, -- ngx.req.get_uri_args()
                                                        body )
    return authorization, awsAuth
end

---
-- Hook to overwrite the request object before sending the request through to AWS
-- By default it returns the same object
-- @param object request object
--
function _M:getRequestObject( object )
    return object
end

function _M:getRequestArguments(actionName, parameters)
    local urlencoded_args = "Action=" .. actionName
    if parameters ~= nil then
        for key,value in pairs(parameters) do
            urlencoded_args = urlencoded_args .. "&" .. key .. "=" .. (value or "")
        end
    end
    return urlencoded_args
end

---
-- Generic function used to call any AWS Service.
-- NOTE: All methods use AWS V4 signature, so this should be compatible with all the new AWS services.
-- More info: http://docs.aws.amazon.com/kms/latest/APIReference/CommonParameters.html
--
-- @param actionName Name of the AWS Action. i.e. GenerateDataKey
-- @param arguments Extra arguments needed for the action
-- @param path AWS Path. Default value is "/"
-- @param http_method Request HTTP Method. Default value is "GET"
-- @param useSSL Call using HTTPS or HTTP. Default value is "HTTP"
--
function _M:performAction(actionName, arguments, path, http_method, useSSL, timeout )
    local host = self:getAWSHost()
    local request_method = http_method or "GET"

    local arguments = arguments or {}
    local query_string = self:getRequestArguments(actionName, arguments )
    local request_path = path or "/"

    local uri_args, request_body = arguments, ""
    uri_args.Action = actionName

    if request_method ~= "GET" then
        uri_args = {}
        request_body = cjson.encode(arguments) -- query_string
    end

    local scheme = "http"
    local port = 80
    if useSSL == true then
        scheme = "https"
        port = 443
    end


    local authorization, awsAuth = self:getAuthorizationHeader(request_method, request_path, uri_args, request_body)

    local t = "TrentService." .. actionName
    local request_headers = {
                    Authorization = authorization,
                    ["X-Amz-Date"] = awsAuth.aws_date,
                    ["Accept"] = "application/json",
--                    ["Content-Type"] = "application/x-www-form-urlencoded",
                    ["Content-Type"] = "application/x-amz-json-1.1",
                    ["X-Amz-Target"] = t
    }

    if request_method == "GET" then
        request_headers["Content-Type"] = "text/plain"
        request_path = request_path .. "?" .. query_string
    end

    self:debug("Calling AWS:", request_method, " ", scheme, "://", host, ":", port, "/", request_path, " ",  request_body)
    self:debug("AWS Header:", "Authorization:", authorization, "X-Amz-Date", awsAuth.aws_date )

    local ok, code, headers, status, body  = self:getHttpClient():request( self:getRequestObject({
            scheme = scheme,
            port = port,
            timeout = timeout or 60000,
            url = request_path, -- "/"
            host = host,
            body = request_body,
            method = request_method,
            headers = request_headers
    }) )

    return ok, code, headers, status, body
end

return _M





