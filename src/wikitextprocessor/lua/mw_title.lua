-- Simplified implementation of mw.title for running WikiMedia Scribunto
-- code under Python
--
-- Copyright (c) 2020-2021 Tatu Ylonen.  See file LICENSE and https://ylonen.org

local mw_title_meta = {
}

function mw_title_meta:__index(key)
    local v = rawget(mw_title_meta, key)
    if v ~= nil then return v end
    if key == "basePageTitle" then
        return mw.title.new(self.baseText, self.nsText)
    end
    if key == "rootPageTitle" then
        return mw.title.new(self.rootText, self.nsText)
    end
    if key == "subjectPageTitle" then
        return mw.title.new(self.text, self.subjectNsText)
    end
    if key == "contentModel" then return "wikitext" end
    if key == "talkPageTitle" then
        local talk_ns = mw.site.namespaces[self.namespace].talk
        if talk_ns == nil then return nil end
        return mw.title.new(self.text, talk_ns.name)
    end
    if key == "protectionLevels" then return { nil } end
    if key == "cascadingProtection" then
        return { restrictions = {}, sources = {} }
    end
    if key == "canTalk" then return false end
    if key == "redirectTarget" then
        return mw.title.new(self._redirectTarget)
    end
    return nil
end

function mw_title_meta.__lt(a, b)
    return a.prefixedText < b.prefixedText
end

function mw_title_meta.__le(a, b)
    return a.prefixedText <= b.prefixedText
end

function mw_title_meta:__tostring()
    return self.prefixedText
end

function mw_title_meta:isSubpageOf(titleobj2)
    assert(type(titleobj2) == "table")
    if self.nsText ~= titleobj2.nsText then return false end
    local t1 = titleobj2.text
    local t2 = self.text
    if #t1 >= #t2 then
        return false
    end
    if mw.ustring.sub(t2, 1, #t1) ~= t1 then
        return false
    end
    if mw.ustring.sub(t2, #t1 + 1, #t1 + 1) ~= "/" then
        return false
    end
    return true
end

function mw_title_meta:inNamespace(ns)
    assert(type(ns) == "string" or type(ns) == "number")
    if type(ns) == "string" then
        -- strip surrounding whitespaces
        ns = ns:gsub("^%s(.-)%s*$", "%1")
    end
    local ns1 = mw.site.namespaces[self.namespace]
    local ns2 = mw.site.namespaces[ns]
    if ns2 == nil then
        return false
    end
    if ns1.name == ns2.name then return true end
    return false
end

function mw_title_meta:inNamespaces(...)
    for i, ns in ipairs({ ... }) do
        if self:inNamespace(ns) then return true end
    end
    return false
end

function mw_title_meta:hasSubjectNamespace(namespace)
    local ns = mw.site.findNamespace(namespace)
    return ns.name == self.subjectNsText
end

function mw_title_meta:subPageTitle(text)
    return mw.title.makeTitle(self.namespace, self.text .. "/" .. text)
end

function mw_title_meta:partialUrl()
    return mw.uri.encode(self.text, "WIKI")
end

function mw_title_meta:fullUrl(query, proto)
    local uri = mw.uri.fullUrl(self.fullText, query)
    if proto ~= nil and proto ~= "" then uri.proto = proto end
    uri.fragment = self.fragment
    uri:update()
    return tostring(uri)
end

function mw_title_meta:localUrl(query)
    return mw.uri.localUrl(self.fullText, query)
end

function mw_title_meta:canonicalUrl(query)
    return mw.uri.canonicalUrl(self.fullText, query)
end

function mw_title_meta:getContent()
    return mw_python_get_page_content(self.fullText, self.namespace)
end

local mw_title = {
    -- equals
    -- compare
    -- getCurrentTitle
    -- new
    -- makeTitle  (see below)
}

function mw_title.makeTitle(namespace, title, fragment, interwiki)
    if title == nil or title == "" then return nil end
    if title:find("%%[0-9a-fA-F][0-9a-fA-F]") then return nil end
    if title:find("<") then return nil end
    if title:find(">") then return nil end
    if title:find("%[") then return nil end
    if title:find("%]") then return nil end
    if title:find("|") then return nil end
    if title:find("{") then return nil end
    if title:find("}") then return nil end
    if title:sub(1, 1) == ":" then return nil end
    if title == "." or title == ".." then return nil end
    if title:sub(1, 2) == "./" or title:sub(1, 3) == "../" then return nil end
    if title:find("/%./") or title:find("/%.%./") then return nil end
    if title:sub(-2) == "/." or title:sub(-3) == "/.." then return nil end
    if #title > 255 then return nil end
    if title:sub(1, 1) == " " or title:sub(-1) == " " then
        title = title:gsub("^%s*(.-)%s*$", "%1")
    end
    if title:find("~~~~") then return nil end
    local prefixes = {
        NAMESPACE_DATA.Talk.name .. ":",
        NAMESPACE_DATA.Project.name .. ":",
        NAMESPACE_DATA.Media.name .. ":",
        NAMESPACE_DATA.File.name .. ":",
        NAMESPACE_DATA.Special.name .. ":",
    }
    for i, v in ipairs(NAMESPACE_DATA.Project.aliases) do
        table.insert(prefixes, v .. ":")
    end
    for i, v in ipairs(NAMESPACE_DATA.File.aliases) do
        table.insert(prefixes, v .. ":")
    end
    -- XXX other disallowed prefixes, see
    -- https://www.mediawiki.org/wiki/Special:Interwiki
    for i, prefix in ipairs(prefixes) do
        if title:sub(1, #prefix) == prefix then return nil end
    end
    -- XXX there are also other disallowed titles, see
    -- https://www.mediawiki.org/wiki/Manual:Page_title
    if not namespace or namespace == "" then namespace = "Main" end
    local ns = mw.site.findNamespace(namespace)
    if not ns then
        return nil
    end
    if interwiki then
        error("XXX unimplemented: mw_title.makeTitle called with interwiki: " ..
            interwiki)
    end
    -- XXX how should interwiki be handled?
    -- w: (wikipedia)
    -- m: (or meta:) for Meta-Wiki
    -- mw: (MediaWiki)
    -- wikt: (Wiktionary)
    -- en: (English)
    -- fr: (French language)
    -- de: (German language)
    -- and other language prefixes
    -- :en: links to English wikipedia etc
    -- interwiki prefixes are case-insensitive
    local isContent = false
    for i, v in pairs(mw.site.contentNamespaces) do
        if mw.site.matchNamespaceName(v, namespace) then
            isContent = true
            break
        end
    end

    -- Copided from: https://github.com/wikimedia/mediawiki-extensions-Scribunto/blob/2ee5768ef565965cf5a5057233c557b281aaa837/includes/Engines/LuaCommon/lualib/mw.title.lua#L85
    local firstSlash, lastSlash
    if ns.hasSubpages then
        firstSlash, lastSlash = string.match(title, '^[^/]*().*()/[^/]*$')
    end
    local isSubpage, rootText, baseText, subpageText
    if firstSlash then
        isSubpage = true
        rootText = string.sub(title, 1, firstSlash - 1)
        baseText = string.sub(title, 1, lastSlash - 1)
        subpageText = string.sub(title, lastSlash + 1)
    else
        isSubpage = false
        rootText = title
        baseText = title
        subpageText = title
    end

    local fullName
    if ns.name == "Main" then
        fullName = title
    else
        fullName = ns.name .. ":" .. title
    end
    local withFrag
    if fragment then
        withFrag = fullName .. "#" .. fragment
    else
        withFrag = fullName
    end

    -- mw_title.python_get_page_info is set in lua_set_fns
    local dt = mw_python_get_page_info(ns.name .. ":" .. title, ns.id)
    local id = dt.id
    local exists = dt.exists
    local redirectTo = dt.redirectTo

    -- print("===")
    -- print("title", title)
    -- print("namespace", ns.id)
    -- print("nsText", nsText)
    -- print("text", title)
    -- print("fullText", withFrag)
    -- print("rootText", root)
    -- print("baseText", parent)
    -- print("subpageText", subpage)
    -- print("exists", exists)

    local t = {
        namespace = ns.id,
        id = id,
        interwiki = interwiki or "",
        fragment = fragment or "",
        nsText = ns.name ~= "Main" and ns.name or "",
        subjectNsText = (ns.subject or ns).name,
        text = title,
        prefixedText = ns.name .. ":" .. title,
        fullText = withFrag,
        rootText = rootText,
        baseText = baseText,
        subpageText = subpageText,
        exists = exists,
        -- XXX file: see https://www.mediawiki.org/wiki/Extension:Scribunto/Lua_reference_manual
        file = nil,
        isContentPage = isContent,
        isExternal = interwiki ~= nil, -- ???
        isLocal = interwiki == nil,  -- ???
        isRedirect = redirectTo ~= nil,
        isSpecialPage = ns.name == NAMESPACE_DATA.Special.name,
        isSubpage = isSubpage,
        isTalkPage = ns.isTalk,
        _redirectTarget = redirectTo,
    }
    setmetatable(t, mw_title_meta)
    return t
end

function mw_title.new(text, namespace)
    if text == nil then return nil end
    if type(text) == "number" then
        error("XXX mw.title.new with id not yet implemented")
    end
    assert(type(text) == "string")
    if not namespace then namespace = "Main" end
    local idx = mw.ustring.find(text, ":")
    if idx ~= nil then
        local ns1 = mw.ustring.sub(text, 1, idx - 1)
        local nsobj = mw.site.findNamespace(ns1)
        if nsobj ~= nil then
            namespace = ns1
            text = mw.ustring.sub(text, idx + 1)
        end
    end
    return mw_title.makeTitle(namespace, text)
end

function mw_title.getCurrentTitle()
    return mw_title.new(mw_current_title_python())
end

function mw_title.equals(a, b)
	return a.interwiki == b.interwiki and
		a.namespace == b.namespace and
		a.text == b.text
end

mw_title_meta.__eq = mw_title.equals

function mw_title.compare(a, b)
    if a.interwiki < b.interwiki then return -1 end
    if a.interwiki > b.interwiki then return 1 end
    if a.nsText < b.nsText then return -1 end
    if a.nsText > b.nsText then return 1 end
    if a.text < b.text then return -1 end
    if a.text > b.text then return 1 end
    return 0
end

return mw_title
