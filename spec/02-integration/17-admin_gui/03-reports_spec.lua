local cjson = require "cjson"

local helpers = require "spec.helpers"
local constants = require "kong.constants"

describe("anonymous reports for kong manager visit", function()

  local dns_hostsfile

  local reports_send_ping = function()
    ngx.sleep(0.2) -- hand over the CPU so other threads can do work (processing the sent data)
    local admin_client = helpers.admin_client()
    local res = admin_client:post("/reports/send-ping?port=" .. constants.REPORTS.STATS_TLS_PORT)
    assert.response(res).has_status(200)
    admin_client:close()
  end

  local assert_km_visits = function (value)
    local reports_server = helpers.tcp_server(constants.REPORTS.STATS_TLS_PORT, {tls=true})
    reports_send_ping()
    local _, reports_data = assert(reports_server:join())
    reports_data = cjson.encode(reports_data)

    assert.match("km_visits=" .. value, reports_data)
  end

  lazy_setup(function()
    dns_hostsfile = assert(os.tmpname() .. ".hosts")
    local fd = assert(io.open(dns_hostsfile, "w"))
    assert(fd:write("127.0.0.1 " .. constants.REPORTS.ADDRESS))
    assert(fd:close())

    local bp = assert(helpers.get_db_utils(nil, {}, { "reports-api" }))

    bp.plugins:insert({
      name = "reports-api",
      config = {}
    })

    assert(helpers.start_kong({
      admin_gui_listen = "127.0.0.1:9012",
      anonymous_reports = true,
      plugins = "bundled,reports-api",
      dns_hostsfile = dns_hostsfile,
    }))
  end)

  lazy_teardown(function()
    os.remove(dns_hostsfile)

    helpers.stop_kong()
  end)

  it("should have value 0 when no kong mananger visit occurs", function ()
    assert_km_visits(0)
  end)

  it("should increase counter by 1 when kong mananger visit occurs", function ()
    local admin_gui_client = helpers.admin_gui_client(nil, 9012)
    assert(admin_gui_client:send({ method = "GET", path = "/" }))
    admin_gui_client:close()

    assert_km_visits(1)
  end)

  it("should reset the counter after report", function ()
    assert_km_visits(0)

    local admin_gui_client = helpers.admin_gui_client(nil, 9012)
    assert(admin_gui_client:send({ method = "GET", path = "/" }))
    admin_gui_client:close()

    assert_km_visits(1)
  end)

  it("should not increase the counter for GUI assets", function ()
    local admin_gui_client = helpers.admin_gui_client(nil, 9012)
    admin_gui_client:send({ method = "GET", path = "/kconfig.js" })
    admin_gui_client:send({ method = "GET", path = "/robots.txt" })
    admin_gui_client:send({ method = "GET", path = "/favicon.ico" })
    admin_gui_client:send({ method = "GET", path = "/test.js" })
    admin_gui_client:send({ method = "GET", path = "/test.css" })
    admin_gui_client:send({ method = "GET", path = "/test.png" })
    admin_gui_client:close()

    assert_km_visits(0)
  end)
end)
