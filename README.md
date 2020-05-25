# resty.limit.count
使用openresty对请求进行限流

http模块引入lua_shared_dict：

```
lua_shared_dict my_limit_req_store 10m;
```

引用lua

```
location / {
			default_type text/html;
      #返回lua中打印：ngx.sqy()
      content_by_lua_file F:/cmccsi/openresty/src/ng_lua_alarm.lua;
      #校验是否通过
#     access_by_lua_file F:/cmccsi/openresty/src/ng_lua_alarm.lua;
}
```


需求每秒限流多少请求
resty.limit.req  为平滑放行，经测试不符合条件
后改为
resty.limit.count 秒过n个请求

req和count都需要根据key进行限流
```
local delay, ierr = lim:incoming(key, true)
```
req key
```
local key = ngx.var.binary_remote_addr
```
count key
```
local key = ngx.req.get_headers()["Authorization"] or "public"
```

因为开始是使用req,key没有改动，在win测试没有报错，在linux报错  not a number  改用后无误

