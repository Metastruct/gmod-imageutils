FindMetaTable"IMaterial".ReloadTexture = function(self,name)
	self:GetTexture(name or "$basetexture"):Download()
end


local IsPNG = string.IsPNG

if not IsPNG then
	include'helpers/imgparse.lua'
	IsPNG = string.IsPNG
end

local IsJPG = string.IsJPG
local IsVTF = string.IsVTF
local PNG = file.ParsePNG
local VTF = file.ParseVTF
local JPG = file.ParseJPG
local N='\r\n'
local VMT_PROTO_TBL = {[["UnlitGeneric"
{
	"$basetexture" "]],nil,[["
	"$vertexcolor" "1"
	"$vertexalpha" "1"
	"$nolod" "1"
}
]]}

local function GenerateVMTForGUI(basetexture)
	VMT_PROTO_TBL[2]=basetexture
	return table.concat(VMT_PROTO_TBL,"")
end

local mw,mh = 	render.MaxTextureWidth(),render.MaxTextureHeight()
mw=mw>2048 and 2048
mh=mh>2048 and 2048

local function MaterialData(path)
	
	local fh = file.Open(path,"rb",'DATA')
	
	local bytes = fh:Read(8)
	fh:Seek(0)
	
	local png = IsPNG(bytes)
	local jpg = not (png or not IsJPG(bytes))
	local vtf = not (png or jpg or not IsVTF(bytes))
	local fmt = png and "png" or jpg and "jpg" or vtf and "vtf"
		
	local w,h
	if png then
		local t = PNG(fh)
		w = t.width or error"dimensions"
		h = t.height or error"dimensions"
	elseif jpg then
		local t = JPG(fh)
		w = t.width or error"dimensions"
		h = t.height or error"dimensions"
	elseif vtf then
		local t = VTF(fh)
		w = t.width or error"dimensions"
		h = t.height or error"dimensions"
	else
		error("invalid file: "..tostring(bytes))
	end
	fh:Close()
	
	if w>mw or h>mh then
		error"too big dimensions"
	end
	
	local path_hacken = string.format("../data/%s\n.%s",path,fmt)

	if vtf then
		
		local vtfpath_hacken = path_hacken
		
		local path_vmt = path:gsub("%.vtf%.dat$",".vmt.dat")
		path_vmt = path == path_vmt and path:gsub("%.dat$",".vmt.dat") or path_vmt
		assert(path ~= path_vmt,"path_vmt == path")
		
		local data_vmt = GenerateVMTForGUI(vtfpath_hacken)
		
		local fh = file.Open(path_vmt,'wb','DATA')
			assert(fh,"could not open vmt")
			fh:Write(data_vmt)
		fh:Close()
		
		
		path_hacken = string.format("../data/%s\n.vmt",path_vmt)
		
	end
	
	local ret = Material( path_hacken, nil )
	
	if ret:IsError() then
		error"invalid material loaded"
	end


	--LocalPlayer():ConCommand("mat_reloadmaterial ../data/" .. path .. "*")
	--ret:ReloadTexture()
	
	return ret,w,h,fmt
end

-- local m1,w1,h1,t1 = MaterialData("hsv8.dat")
-- print(m1,m1 and m1:IsError(),w1,h1,t1)

-- hook.Add("HUDPaint","a",function()
-- surface.SetMaterial(m1)
-- if not w then return end
-- surface.SetDrawColor(255,255,255,255)
-- surface.DrawTexturedRect(0,0,256,256)
-- end)

local PROCESSING=false
local READY=true

local cache = {}

local FOLDER="download_cache"
file.CreateDir(FOLDER,'DATA')

function GetImageCache()
	return cache
end

function surface.GetURLImage(url)
	local c = cache[url]
	if c then
		local state = c[1]
		if state==PROCESSING then return end
		if state~=READY then return false,state end
		return true,c[2],c
	-- else -- process!
	end

	c = {PROCESSING,false,184,184}
	cache[url] = c
	
	local path = FOLDER..'/'..util.CRC(url)..'.dat'
	
	local exists=file.Exists(path,'DATA')
	if exists then
	
		local ok,mat,w,h = pcall(MaterialData,path)

		if not ok or not mat or mat:IsError() then
			Msg"[URLImage] "print("Material found, but is invalid")
			c[1] = "invalid file loaded"
			return false,c[1],c
		else
			c[1]=READY
			c[2]=mat
			c[3]=w or assert(false)
			c[4]=h or assert(false)
			return true,c[2],c
		end
		
	end
	
	local function fail(err)
		Msg"[URLImage] "print("Http fetch failed for",url,": "..tostring(err))
		c[1]=c[1]==PROCESSING and "downloadfail" or c[1]
	end
	
	http.Fetch(url,function(data,len,hdr,code)
		if code~=200 or len<=222 then
			return fail(code)
		end
		
		file.Write(path,data)
		
		local ok,mat,w,h = pcall(MaterialData,path)

		if not ok or not mat or mat:IsError() then
			Msg"[URLImage] "print("Downloaded material, but is error: ",name,"err: ",mat or "?","deleting")
			
			file.Delete(path)
			
			c[1]="download failed"
			return
		end
		
		c[1]=READY
		c[2]=mat
		c[3]=w or assert(false)
		c[4]=h or assert(false)
		
	end,fail)
	
	return nil
	
end

local GetURLImage=surface.GetURLImage
function surface.URLImage(name)
	local ok,mat,c = GetURLImage(name)
	local w,h
	if ok==true then
		
		assert(not mat:IsError())
		w=c[3]
		h=c[4]
		return function()
			surface.SetMaterial(mat)
			return w,h,mat
		end
	end
	
	mat=nil

	return function()
		if not mat then
			ok,mat,c = GetURLImage(name)
			if not ok then
				mat=nil
				surface.SetTexture(0)
				return
			else
				w=c[3] or assert(false,"dimensions missing?")
				h=c[4] or assert(false,"dimensions missing?")
				c = nil
			end
		end
		
		surface.SetMaterial(mat)
		return w,h,mat
	end
end

-- local test = surface.URLImage "http://g3.metastruct.org:20080/hsv8.vtf"
-- hook.Add("HUDPaint","a",function()
-- 	local w,h = test()
-- 	if not w then return end
-- 	surface.SetDrawColor(255,255,255,255)
-- 	surface.DrawTexturedRect(0,0,w,h)
-- end)