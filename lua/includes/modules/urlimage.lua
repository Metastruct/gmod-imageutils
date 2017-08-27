if SERVER then
	AddCSLuaFile() return
end

module("urlimage",package.seeall)
_M._MM = setmetatable({},{__index=function(s,k) return rawget(s,k) end,__newindex=_M})
function dbg(...) Msg"[UrlImg] "print(...) end
function DBG(...) Msg"[UrlImg] "print(...) end

-- no debug anymore
dbg=function()end

FindMetaTable"IMaterial".ReloadTexture = function(self,name)
	self:GetTexture(name or "$basetexture"):Download()
end

-- texture parsers for real w/h
local IsPNG = string.IsPNG
if not IsPNG then include'helpers/imgparse.lua' IsPNG = string.IsPNG end
local IsJPG = string.IsJPG
local IsVTF = string.IsVTF

local PNG = file.ParsePNG
local VTF = file.ParseVTF
local JPG = file.ParseJPG

require'sqlext'
--
local db = assert(sql.obj("urlimage")
	--:drop()
	:create([[
		`url`		TEXT NOT NULL CHECK(url <> '') UNIQUE,
		`ext`		TEXT NOT NULL CHECK(ext = 'vtf' OR ext = 'png' OR ext = 'jpg'),
		`last_used`	INTEGER NOT NULL DEFAULT 0,
		`fetched`	INTEGER NOT NULL DEFAULT (cast(strftime('%%s', 'now') as int) - 1477777422),
		`locked`	BOOLEAN NOT NULL DEFAULT 1,
		`w`			INTEGER(2) NOT NULL DEFAULT 0,
		`h`			INTEGER(2) NOT NULL DEFAULT 0,
		`fileid`	INTEGER PRIMARY KEY AUTOINCREMENT]])
	:coerce{last_used=tonumber, fileid=tonumber,w=tonumber,h=tonumber, locked=function(l) return l=='1' end })

local l = assert(db:update("locked = 0 WHERE locked != 0"))

if l>0 then dbg("unlocked entries: ",l) end

-- print(db:columns())

--  Msg"insert " 		print(assert(		db:insert{url = "http://asd.com/0", last_used = os.time()}))
--  Msg"replace " 		print(				db:insert({url = "http://asd.com/0", last_used = 1337},true))
--  Msg"insert " 		print(assert(		db:insert{url = "http://asd.com/1", last_used = os.time()-123}))
--  Msg"count " 		print(tonumber(		db:select1"count(*) as count".count))
--  Msg"Delete none " 	PrintTable(assert(	db:delete("url = %s",'derp')))
--  Msg"count " 		print(tonumber(		db:select1"count(*) as count".count))
--  Msg"list "			PrintTable(			db:select("*","WHERE URL != %s","http://asd.co"))
--  Msg"update "		PrintTable(			db:update("locked = 1 WHERE fileid=%d",123))
--  Msg"list"			PrintTable(			db:select("*","WHERE URL != %s","http://asd.co"))
--  Msg"raw"			PrintTable(assert(	db:sql1("select * from %s limit %d",db,1)))
--  Msg"Delete all " 	print(assert(		db:delete("url != %s",'derp')))
--do return end
---------------

local MAX_ENTRIES = 128
local function find_purgeable()
	dbg("find_purgeable()")
	local a,b = db:select('*','WHERE locked != 1 ORDER BY last_used LIMIT(select max(0,count(*) -%d) from %s)',MAX_ENTRIES,db)
	return a,b
end

function update_dimensions(fileid,w,h)
	dbg("update_dimensions()",fileid,w,h)
	assert(tonumber(fileid))
	return db:update("w = %d, h=%d WHERE fileid=%d",w,h,fileid)
end

function record_use(fileid,nolock)
	dbg("record_use()",fileid,nolock)
	assert(tonumber(fileid))
	nolock = nolock and "" or ", locked = 1"
	return db:update("last_used = (cast(strftime('%%s', 'now') as int) - 1477777422)"..nolock.." WHERE fileid=%d",fileid)
end

function get_record(urlid)
	dbg("get_record()",urlid)
	local record = assert(db:select1('*',isnumber(urlid) and "WHERE fileid = %d" or "WHERE url = %s",urlid))
	return record~=true and record
end

function record_validate(r)
	if not istable(r) then r = get_record(r) end
	dbg("record_validate()",r,r and r.url or r.fileid)
	if not r or not r.w or r.w==0 then return false end
	
	return r and file.Exists(FPATH(r.fileid,r.ext),'DATA') and r
end

function new_record(url,ext)
	dbg("new_record()",url,ext)
	local fileid = assert(db:insert{url = url,ext = ext})
	return fileid
end

--print(update_last_used(db:insert{url = "f"}))
--db:insert{url = "http://asd.com/1",last_used = 1}
--db:insert{url = "http://asd.com/2",ext="jpg"}
--db:insert{url = "http://asd.com/3",last_used = 3}
--db:insert{url = "http://asd.com/4"}
--Msg"list "			PrintTable(			db:select("*","WHERE URL != %s","http://asd.co"))

BASE = "cache/uimg"
file.CreateDir("cache",'DATA')
file.CreateDir(BASE,'DATA')
function FPATH(a,ext,open_as)
	--Msg(("FPATH %q %q %q -> "):format(a or "",ext or "",tostring(open_as or "")))
	if ext=="vmt" then
		a=a..'_vmt'
		ext="txt"
	end
	
	local ret =("%s/%s%s%s%s%s"):format(BASE,tostring(a),
		ext and "." or "",
		ext or "",
		open_as and "\n." or "",
		open_as or "")
	--print(ret)
	return ret
end

function FPATH_R(...)
	return ("../data/%s"):format(FPATH(...))
end

local generated = {}
function Material(fileid, ext, isSurface, ...)
	dbg("Material()",fileid,ext,...)
	local path = FPATH_R(fileid,ext )
	local a,b
	
	if ext == 'vtf' then
		path = FPATH_R(fileid)
		dbg("_G.CreateMaterial()",("%q"):format(path))
		a,b = CreateMaterial("uimgg"..fileid .. (isSurface and "surface" or "render"), isSurface and "UnlitGeneric" or "VertexLitGeneric", {
			["$vertexcolor"] = "1",
			["$vertexalpha"] = "1",
			["$nolod"] = "1",
			["$basetexture"] = path,
			["Proxies"] =
			{
				["AnimatedTexture"] =
				{
					["animatedTextureVar"] = "$basetexture",
					["animatedTextureFrameNumVar"] = "$frame",
					["animatedTextureFrameRate"] = 8,
				}
			}
		})
	else
		dbg("_G.Material()",("%q"):format(path))
		a,b = _G.Material(path,...)
	end
	
	-- should no longer be needed, if it even works
	--if a then a:ReloadTexture() end
	
	return a,b,path
end

function fwrite(fileid,ext,data)
	dbg("fwrite()",fileid,ext,#data)
	local path = FPATH(fileid,ext)
	file.Write(path,data)
	return path
end
function fopen(fileid,ext)
	dbg("fopen()",fileid,ext)
	return file.Open(FPATH(fileid,ext),'rb','DATA')
end

local delete_record delete_record = function(record)
	dbg("delete_record()",record)
	if istable(record) then
		
		if next(record)==nil then return 0 end
		
		if record[1] then
			local aggr = 0
			for k,record in next,record do
				aggr = aggr + assert(delete_record(record))
			end
			return aggr
		else
			return delete_record(record.fileid or record.fileid)
		end
	elseif isnumber(record) then
		return db:delete('fileid = %d',record)
	elseif isstring(record) then
		return db:delete('url = %s',record)
	else error"wtf" end
end

function delete_fileid(fileid,ext)
	dbg("delete_fileid()",fileid,ext)
	if ext then
		return file.Delete(FPATH(fileid,ext),'DATA')
	end
	file.Delete(FPATH(fileid,'vmt'),'DATA')
	file.Delete(FPATH(fileid,'jpg'),'DATA')
	file.Delete(FPATH(fileid,'png'),'DATA')
	file.Delete(FPATH(fileid,'vtf'),'DATA')
end


--TODO: Purge on start and live
local purgeable = assert(find_purgeable())
if purgeable~=true then
	dbg("LRU Purge: ",#purgeable)
end


function data_format(bytes)
	if 		IsJPG(bytes) then return 'jpg'
	elseif 	IsPNG(bytes) then return 'png'
	elseif 	IsVTF(bytes) then return 'vtf'
	end
	dbg("data_format()","FAILURE",("%q"):format(bytes))
end

local mw,mh = 	render.MaxTextureWidth(),render.MaxTextureHeight()
mw=mw>2048 and 2048 mh=mh>2048 and 2048
function read_image_dimensions(fh,fmt)
	dbg("read_image_dimensions()",fh,fmt)
	local reader = fmt=='png' and PNG or fmt=='jpg' and JPG or fmt=='vtf' and VTF
	if not reader then return nil,'No reader for format: '..tostring(fmt) end
	
	local w,h
	local t = reader(fh)
	
	w = t.width
	h = t.height
	if not w or not h then
		return nil,'invalid file'
	end
	if w>mw or h>mh then
		return nil,'excessive dimensions'
	end
	return w,h
end

function record_to_material(r, data, isSurface)
	dbg("record_to_material()",r and r.fileid)
	if not r.used then
		assert(record_use(r.fileid))
		r.used = true
	end
	return Material(r.fileid, r.ext, isSurface, data), r.w, r.h
end

local function remove_error(cached,...)
	cached.error = nil
	return ...
end

cache = _MM.cache or {}
local cache = cache

local fastdl = GetConVarString"sv_downloadurl":gsub("/$","")..'/'

function FixupURL(url)
	if not url:sub(3,10):find("://",1,true) then
		url = fastdl..url
	else

		url = url:gsub([[^http%://onedrive%.live%.com/redir?]],[[https://onedrive.live.com/download?]])
		url = url:gsub( "github.com/([a-zA-Z0-9_]+)/([a-zA-Z0-9_]+)/blob/", "github.com/%1/%2/raw/")

		if url:find("dropbox",1,true) then
			url = url:gsub([[^http%://dl%.dropboxusercontent%.com/]],[[https://dl.dropboxusercontent.com/]])
			url = url:gsub([[^https?://www.dropbox.com/s/(.+)%?dl%=[01]$]],[[https://dl.dropboxusercontent.com/s/%1]])
		end

	end
	
	return url
end

-- Returns: mat,w,h
-- Returns: false = processing, nil = error
function GetURLImage(url, data, isSurface)
	
	url = FixupURL(url)
	
	local cached = cache[url]
	if cached then
		if cached.processing then
			return false
		elseif cached.error then
			return nil,cached.error
		elseif cached.record then
			return record_to_material(cached.record, data, isSurface)
		else
			cached.error = "invalid cache state"
			error(cached.error)
		end
	end
	
	-- find if record exists --
	
	cached = {error = "failure"}
	cache[url] = cached
	
	local cached_record = get_record(url)
	if cached_record then
		
		assert(next(cached_record)~=nil)
		
		if record_validate(url) then
			record_use(cached_record.fileid)
			cached.record = cached_record
			return remove_error(cached, record_to_material(cached_record, data, isSurface) )
		else
			DBG("INVALID RECORD","DELETING",url)
			assert(delete_record(url))
		end
	end
	
	-- it's a new url --
	dbg("Fetching",url)
	
	local function fail(err)
		delete_record(url)
		cached.processing = false
		cached.error = tostring(err)
		dbg("Fetch failed for",url,": "..cached.error)
	end
	
	local function fetched(data,len,hdr,code)
		
		dbg("fetched()",len,code)
		
		if code~=200 then
			return fail(code)
		end
		if len<=8 or len>16778216 then -- 4*2048*2048 + 1kb
			return fail'invalid filesize'
		end
		
		local ext = data_format(data)
		if not ext then
			return fail'unknown format'
		end
		
		-- build a new record --
		
		local fileid = new_record(url,ext)
		local record = {fileid = fileid}
		
		fwrite(fileid,ext,data) data = nil
		local fh = fopen(fileid,ext)
		
		local w,h = read_image_dimensions(fh,ext)
		fh:Close()
		if not w then return fail(h) end
		
		update_dimensions(fileid,w,h)
		
		
		-- We don't have to build the record manually, we can just get it again
		cached.record = get_record(url)
		
		if not record_validate(cached.record) then
			return fail'record_validate()'
		end
		
		-- we now have some sort of record, so let's use it so it's top of LRU
		record_use(fileid,true) -- maybe remove?
		
		cached.processing = false
		remove_error(cached)
		
		
	end
	
	http.Fetch(url,fetched,fail)
	
	cached.processing = true
	
	return false
	
end


function surface.URLImage(url, data)
	local mat,w,h = GetURLImage(url, data, true)
	local function setmat()
		surface.SetMaterial(mat)
		return w,h, mat
	end
	
	if mat then
		dbg("URLImage",url,"instant mat",mat)
		return setmat
	end
	
	local trampoline trampoline = function()
		mat,w,h = GetURLImage(url, data, true)
		if not mat then
			if mat==nil then
				trampoline = function() end
				DBG("URLImage failed for ",url,": ",w,h)
			end
			
			return
		end
		trampoline = setmat
		return setmat()
	end
	
	return function()
		return trampoline()
	end
	
end

function render.URLMaterial(url, data)
	local mat,w,h = GetURLImage(url, "vertexlitgeneric " .. (data or ""), false)
	local function setmat()
		render.SetMaterial(mat)
		return w,h, mat
	end
	
	if mat then
		dbg("URLImage",url,"instant mat",mat)
		return setmat
	end
	
	local trampoline trampoline = function()
		mat,w,h = GetURLImage(url, "vertexlitgeneric " .. (data or ""), false)
		if not mat then
			if mat==nil then
				trampoline = function() end
				DBG("URLImage failed for ",url,": ",w,h)
			end
			
			return
		end
		trampoline = setmat
		return setmat()
	end
	
	return function()
		return trampoline()
	end
	
end


do return end

local test1 = surface.URLImage "materials/silk_icon_flags.png?b=cdq"
local test2 = surface.URLImage "http://g1.metastruct.net:2095/jpg.jpg?c=dqd"
local test3 = surface.URLImage "http://g1.metastruct.net:2095/vtf.vtf?c=qdq"
hook.Add("DrawOverlay","a",function()
	surface.SetDrawColor(255,255,255,255)
 
	local w,h = test1()
	if w then
		--print(w)
		surface.DrawTexturedRect(0,0,w,h)
	end
	local w1,h1 = test2()
	if w1 then
		surface.DrawTexturedRect(1+(w or 0),0,w1,h1)
	end
	local w2,h2 = test3()
	if w2 then
		surface.DrawTexturedRect(2+(w or 0)+(w1 or 0),0,w2,h2)
	end
end)
 