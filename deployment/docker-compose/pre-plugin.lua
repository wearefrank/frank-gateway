return function(conf, ctx) 
    local soap_action = ngx.req.get_headers()['SOAPAction']
    local core = require('apisix.core')
    if soap_action ~= nil then
        ngx.log(ngx.ERR, 'SOAPAction ', soap_action)
        core.ctx.register_var('soap_action', function(ctx)
            return soap_action
        end)

    else
        local xml2lua = require('xml2lua')
        local xmlhandler = require('xmlhandler.tree')
        local body = core.request.get_body()
        if body ~= nil then 
            local handler = xmlhandler:new()
            local parser = xml2lua.parser(handler)
            parser:parse(body)
            local soap_body = handler.root['soap:Envelope']['soap:Body']

            for key, value in pairs(soap_body) do
                ngx.log(ngx.ERR, 'soap_body ', key, vaSlue)
            end

        end
    end
    ngx.log(ngx.ERR, 'match uri ', ctx.curr_req_matched and ctx.curr_req_matched._path)
end