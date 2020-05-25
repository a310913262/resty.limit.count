local limit_count = require "resty.limit.count"
local cjson = require("cjson")
local producer = require("resty.kafka.producer")
local redis = require "resty.redis"
--local ip = "127.0.0.1"
local rip = "***********"
local port = 6379
local red = redis:new()
red:set_timeout(1000)
local cok, cerr = red:connect(rip, port)
if not cok then
    ngx.log(ngx.ERR, "failed to connect", cerr)
    return
end
local res, err = red:auth("*********")
if not res then
    ngx.log(ngx.ERR, "failed to authenticate: ", err)
    return
end

--下面的调用必须是每个请求,在这里我们使用远程ip(相当于客户端的ip)作为限制key值
--local key = ngx.var.binary_remote_addr
local key = ngx.req.get_headers()["Authorization"] or "public"
local headers = ngx.req.get_headers()
local ip = headers["X-REAL-IP"] or headers["X_FORWARDED_FOR"] or ngx.var.remote_addr or "0.0.0.0"
local get, gerr = red:get(ip)
if get ~= ngx.null then
    ngx.log(ngx.ERR, "redis 黑名单拦截")
    return ngx.exit(403)
else
    local broker_list = {
        { host = "0.0.0.0", port = 9092 }

    }
    --ip动态限流key
    local limitkey = "req:limit:" .. ip
    --获取redis中是否单独限流
    local lget, lerr = red:get(limitkey)
    local lim, err
    if lget ~= ngx.null then
        lim, err = limit_count.new("my_limit_req_store", tonumber(lget), 1)
    else
        local limitkeydef = "req:limit:0.0.0.0"
        local dget, derr = red:get(limitkeydef)
        if dget ~= ngx.null then
            --获取默认ip限制
            lim, err = limit_count.new("my_limit_req_store", tonumber(dget), 1)
        else
            --没有默认设置100
            lim, err = limit_count.new("my_limit_req_store", 100, 1)
        end
    end

    if not lim then
        ngx.log(ngx.ERR, "failed to instantiate a resty.limit.req object: ", err)
        return ngx.exit(500)
    end
    local delay, ierr = lim:incoming(key, true)
    if not delay then
        if ierr == "rejected" then
            ngx.log(ngx.ERR, "redis get为空,第一次拦截")
            red:set(ip, "1")
            red:expire(ip, 60 * 3)
            local uri = ngx.var.uri

            local result_json = {}
            if "GET" == ngx.req.get_method() then
                result_json["agrs"] = ngx.req.get_uri_args()
            elseif "POST" == ngx.req.get_method() then
                result_json["agrs"] = ngx.req.get_uri_args()
                ngx.req.read_body()
                result_json["body"] = ngx.req.get_body_data()
            end
            result_json["method"] = ngx.req.get_method()
            result_json["ip"] = ip
            result_json["time"] = ngx.localtime()
            result_json["uri"] = uri
            local message = cjson.encode(result_json);
            local async_producer = producer:new(broker_list, { producer_type = "async" })
            local kok, kerr = async_producer:send("limit.alarm", "key", message)
            if not kok then
                ngx.log(ngx.ERR, "kafka send err:", kerr)
                return
            end
            ngx.log(ngx.ERR, "拦截")
            return ngx.exit(403)
        end
        ngx.log(ngx.ERR, "failed to limit req: ", ierr)
        return ngx.exit(500)
    end
end
