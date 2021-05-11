#!/usr/local/bin/lua



local cgilua = require "cgilua"
local urlcode = require "cgilua.urlcode"
local rex   = require "rex_pcre"
local https = require "ssl.https"
local http  = require "socket.http"
local cjson = require "cjson"



function html_links_to_gmi_links(str)
    -- str = string.gsub(str, "%%", "%%%%")

    for w, p, d, t, tw in rex.gmatch(str, "<a([\\s]+)href=\"(\\w+://)([.A-Za-z0-9?=:|;,_#^\\-/%+&~\\(\\)@!]+)\" target=\"_blank\">(.+?)</a>([\\s]*)", "is", nil) do

        local gmi_link = '\n\n=> ' .. p .. d .. '    ' .. t .. '\n\n'
        gmi_link = string.gsub(gmi_link, "%%", "%%%%")

        str = rex.gsub(str , '<a' .. w .. 'href="' .. p .. d .. '" target="_blank">' .. t .. '</a>' .. tw, gmi_link , nil, "is")
    end
    return str
end



function is_empty(s)
  return s == nil or s == ''
end



function remove_html (str)
    local tmp_str = rex.gsub(str, "<([^>])+>|&([^;])+;", "", nil, "sx")
    if is_empty(tmp_str) then
        return str
    else
        return tmp_str
    end
end



function url_encode(str)
   if str then
      str = str:gsub("\n", "\r\n")
      str = str:gsub("([^%w %-%_%.%~])", function(c)
         return ("%%%02X"):format(string.byte(c))
      end)
      str = str:gsub(" ", "+")
   end
   return str
end


function table_print (tt, indent, done)
  done = done or {}
  indent = indent or 0
  if type(tt) == "table" then
    for key, value in pairs (tt) do
      io.write(string.rep (" ", indent)) -- indent it
      if type (value) == "table" and not done [value] then
        done [value] = true
        io.write(string.format("[%s] => table\n", tostring (key)));
        io.write(string.rep (" ", indent+4)) -- indent it
        io.write("(\n");
        table_print (value, indent + 7, done)
        io.write(string.rep (" ", indent+4)) -- indent it
        io.write(")\n");
      else
        io.write(string.format("[%s] => %s\n",
            tostring (key), tostring(value)))
      end
    end
  else
    io.write(tt .. "\n")
  end
end



function split(str, pat)
   local t = {}  -- NOTE: use {n = 0} in Lua-5.0
   local fpat = "(.-)" .. pat
   local last_end = 1
   local s, e, cap = str:find(fpat, 1)
   while s do
      if s ~= 1 or cap ~= "" then
         table.insert(t,cap)
      end
      last_end = e+1
      s, e, cap = str:find(fpat, last_end)
   end
   if last_end <= #str then
      cap = str:sub(last_end)
      table.insert(t, cap)
   end
   return t
end




function report_error(str)
    io.write("20 text/gemini\r\n")
    io.write("Unexpected Error: " .. str .. "\r\n")
end



function url_decode(str)
   str = str:gsub("+", " ")
   str = str:gsub("%%(%x%x)", function(h)
      return string.char(tonumber(h,16))
   end)
   str = str:gsub("\r\n", "\n")
   return str
end



function trim_spaces (str)
    if (str == nil) then
        return nil
    end
   
    -- remove leading spaces 
    str = string.gsub(str, "^%s+", "")

    -- remove trailing spaces.
    str = string.gsub(str, "%s+$", "")

    return str
end



function fetch_url(url)
    local body,code,headers,status

    body,code,headers,status = http.request(url)

    if code < 200 or code >= 300 then
        body,code,headers,status = https.request(url)
    end

    if type(code) ~= "number" then
        code = 500
        status = "url fetch failed"
    end

    return body,code,headers,status
end



function create_gmi(t_article, link, t_images)

    local encoded_url = url_encode(link)

    local gmi = "# " .. t_article.title .. "\n\n" 

    if t_article.teaser ~= nil and t_article.teaser ~= "" then
        local teaser = string.gsub(t_article.teaser, "&nbsp;", " ")
        gmi = gmi .. "### " .. teaser .. "\n\n"
    end

    gmi = gmi .. t_article.author .. "\n"
    gmi = gmi .. t_article.displayUpdateDate .. "\n\n"
    gmi = gmi .. "=> " .. link .. " link\n\n" 

    local html_text = string.gsub(t_article.body, "\n", "\n\n")

    html_text = html_links_to_gmi_links(html_text)

    local plain_text = remove_html(html_text)

    gmi = gmi .. plain_text

    return gmi 
end



function gmi_print(gmi_text)
    io.write("20 text/gemini\r\n")
    io.write(gmi_text .. "\r\n")
end

---



local url

local t = {}
-- urlcode.parsequery (os.getenv("QUERY_STRING"), t)
-- url = t.url

local url = os.getenv("QUERY_STRING")

-- url = "https://www.toledoblade.com/local/Coronavirus/2020/11/19/lucas-county-issues-28-day-stay-at-home-advisory/stories/20201119094"


if url == nil or url == "" then
    io.write("10 url=http://...\r\n")
else
    url = url_decode(url)
    local body, code, headers, status = fetch_url(url)

    if code >= 300 then
        report_error("Error: Could not fetch " .. url .. ". Status: " .. status)
    else
        body = trim_spaces(body)

        if body == nil or string.len(body) < 1 then
            report_error("Error: Nothing returned to parse for URL " .. url)
        else
            local article_body = rex.match(body, '"storyID": "(.*)"link": "', 1, "si")
            local json_text = '{"storyID": "' .. article_body .. '"dummy": "test"}'
            local article_table = cjson.decode(json_text)

            local images_body = rex.match(body, '"images": (.*)"related": ', 1, "si")

            local images_table = {}

            if images_body and string.len(images_body) > 0 then
                images_body = images_body:sub(1, -11)
                local images_json_text = '{"images": ' .. images_body .. '}'
                images_table = cjson.decode(images_json_text)
            end

            gmi_print(create_gmi(article_table, url, images_table))
        end
    end
end




