-- KMS Client
-- Created by IntelliJ IDEA.
-- User: ddascal
-- Date: 21/11/14
-- Time: 16:16
-- To change this template use File | Settings | File Templates.


local AwsService = require"api-gateway.aws.AwsService"
local cjson = require"cjson"
local error = error

local _M = AwsService:new({___super = true})
local super = {
    instance = _M,
    constructor = _M.constructor
}

function _M.new(self,o)
    ngx.log(ngx.DEBUG, "KmsService() o=", tostring(o)  )
    local o = o or {}
    o.aws_service = "kms"

    super.constructor(_M, o)

    setmetatable(o, self)
    self.__index = self
    return o
end

function _M:constructor(o)
    ngx.log(ngx.DEBUG, "KmsService() constructor " )
end

-- API: http://docs.aws.amazon.com/kms/latest/APIReference/API_GenerateDataKey.html
-- Request
--    {
--        "EncryptionContext":
--            {
--                "string" :
--                    "string"
--            },
--        "GrantTokens": [
--            "string"
--        ],
--        "KeyId": "string",
--        "KeySpec": "string",
--        "NumberOfBytes": number
--    }
-- Response
--    {
--        "CiphertextBlob": blob,
--        "KeyId": "string",
--        "Plaintext": blob
--    }
function _M:generateDataKey(keyId, keySpec, numberOfBytes, encryptionContext, grantTokens)
    assert(type(keyId) == "string", "generateDataKey() expects a valid keyId as the first argument")
    local arguments = {
        KeyId = keyId,
        KeySpec = keySpec,
        EncryptionContext = encryptionContext,
        GrantTokens = grantTokens,
        NumberOfBytes = numberOfBytes
    }
    local ok, code, headers, status, body = self:performAction("GenerateDataKey", arguments, "/", "POST", true, 60000)

    if (code == ngx.HTTP_OK and body ~= nil) then
        return cjson.decode(body), code, headers, status, body
    end
    return nil, code, headers, status, body
end

-- API: http://docs.aws.amazon.com/kms/latest/APIReference/API_Decrypt.html
-- Request
--    {
--        "CiphertextBlob": blob,
--        "EncryptionContext":
--            {
--                "string" :
--                    "string"
--            },
--        "GrantTokens": [
--            "string"
--        ]
--    }
function _M:decrypt(cipherText, encryptionContext, grantTokens)
    assert(type(cipherText) == "string", "decrypt() expects a valid cipherText as the first arguments")
    local arguments = {
        CiphertextBlob = cipherText,
        EncryptionContext = encryptionContext,
        GrantTokens = grantTokens
    }
    local ok, code, headers, status, body = self:performAction("Decrypt", arguments, "/", "POST", true, 60000)

    if (code == ngx.HTTP_OK and body ~= nil) then
        return cjson.decode(body), code, headers, status, body
    end
    return nil, code, headers, status, body
end

-- API: http://docs.aws.amazon.com/kms/latest/APIReference/API_Encrypt.html
--    {
--        "EncryptionContext":
--            {
--                "string" :
--                    "string"
--            },
--        "GrantTokens": [
--            "string"
--        ],
--        "KeyId": "string",
--        "Plaintext": blob
--    }
function _M:encrypt(keyId, plaintext, encryptionContext, grantTokens)
    assert(type(keyId) == "string", "encrypt() expects a valid keyId as the first argument")
    assert(type(plaintext) == "string", "encrypt() expects a valid plaintext as the second argument")
    local arguments = {
        KeyId = keyId,
        Plaintext = plaintext,
        EncryptionContext = encryptionContext,
        GrantTokens = grantTokens
    }
    local ok, code, headers, status, body = self:performAction("Encrypt", arguments, "/", "POST", true, 60000)

    if (code == ngx.HTTP_OK and body ~= nil) then
        return cjson.decode(body), code, headers, status, body
    end
    return nil, code, headers, status, body
end

-- API: http://docs.aws.amazon.com/kms/latest/APIReference/API_ListAliases.html
-- {
--    "Limit": number,
--    "Marker": "string"
-- }
function _M:listAliases(limit, marker)
    local arguments = {
        Limit = limit,
        Marker = marker
    }
    local ok, code, headers, status, body = self:performAction("ListAliases", arguments, "/", "POST", true, 60000)

    if (code == ngx.HTTP_OK and body ~= nil) then
        return cjson.decode(body), code, headers, status, body
    end
    return nil, code, headers, status, body
end

return _M

