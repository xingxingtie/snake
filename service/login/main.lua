local skynet = require("skynet")
local protopack = require("protopack")
local ErrorCode = require("proto.errorCode")
local genid = require("genid")
local dbtable = require("common.dbtable")

local CMD = {}
local id = 1

--发送数据到前端
function sendLoginInfo(fd, retcode, id, account, token)
    protopack.send_data(fd, "s2c_login", {
        retCode = retcode,
        id      = id,
        account = account,
        token   = token})
end

--发送数据到前端
function sendRigsterInfo(fd, retcode)
    protopack.send_data(fd, "s2c_register", {
        retCode = retcode})
end

--
function CMD.start()

end

--在数据库中创建新的玩家
function createNewUser(account, password, userid)
    --插入playerinfor数据
    local cmd = string.format("insert into %s (account, password, userid) values ('%s', '%s', %d)", 
        "playerinfo", 
        account, 
        password,
        userid)

    skynet.call("dbserver", "lua", "query", cmd)
    
    --插入gameinfo数据
    local cmd = string.format("insert into %s (userid, wincount, losecount) values (%d, %d, %d)", 
        "gameinfo", 
        userid, 
        0,
        0)

    skynet.call("dbserver", "lua", "query", cmd)
    
    return true
end

--注册
function CMD.register(tab, fd)
    --账号为空
    if string.len(tab.account) == 0 then 
        sendRigsterInfo(fd, ErrorCode.ACCOUNT_EMPTY)
        return false 
    end

    --密码为空
    if string.len(tab.password) == 0 then 
        sendRigsterInfo(fd, ErrorCode.PASSWORD_EMPTY)
        return false 
    end

    local whereSql = dbtable.genWhereSql(tab, {"account"})
    local ret = skynet.call("dbserver", "lua", "select", "playerinfo", whereSql)

    --账号已被注册
    if ret then 
        sendRigsterInfo(fd, ErrorCode.ACCOUT_EXIST)
        return false
    end

    if not createNewUser(tab.account, tab.password, genid.gen_userid()) then 
        return false
    end

    sendRigsterInfo(fd, ErrorCode.OK)
    return true
end

--验证
function CMD.verify(tab, fd)
    local whereSql = dbtable.genWhereSql(tab, {"account"})
    local ret = skynet.call("dbserver", "lua", "select", "playerinfo", whereSql)

    --没有该玩家
    if not ret then 
        sendLoginInfo(fd, ErrorCode.NO_ACCOUNT)
        return false
    end

    --密码错误
    if ret.password ~= tab.password then 
        sendLoginInfo(fd, ErrorCode.WRONG_PASSWORD)
        return false
    end

    --正确
    sendLoginInfo(fd, 0, ret.userid, tab.account, "token")

    return true, ret.userid, tab.account
end

skynet.start(function() 
     skynet.dispatch("lua", function(_, _, cmd, ...)
        local f = CMD[cmd]
        if f then 
            skynet.ret(skynet.pack(f(...)))
            return
        end
    end)
end)