local setmetatable = setmetatable
local table        = table
local pairs        = pairs
local ipairs       = ipairs
local next         = next
local type         = type
local print        = print
local string       = string
local math         = math
local button       = require( "awful.button"     )
local beautiful    = require( "beautiful"        )
local widget2      = require( "awful.widget"     )
local config       = require( "config"           )
local util         = require( "awful.util"       )
local wibox        = require( "wibox"            )
local checkbox     = require( "widgets.checkbox" )
local color        = require( "gears.color"      )
local cairo        = require( "lgi"              ).cairo

local capi = { image      = image      ,
               widget     = widget     ,
               mouse      = mouse      ,
               screen     = screen     ,
               keygrabber = keygrabber }

local module={}

-- Common function
local grabKeyboard = false
local currentMenu  = nil
local discardedItems = {}

local function prevent_toolbar_overlap(x_or_y,width_or_height)
    local w_h,x_y = capi.screen[capi.mouse.screen].geometry[width_or_height],capi.mouse.coords()[x_or_y]
    if x_y < 16 then
        return 16
    elseif x_y > w_h-16 then
        return w_h-16
    end
    if x_or_y == "x" and x_y - 37 > 0 then
        x_y = x_y - 37
    end
    return x_y
end

local function draw_border(menu,item,args)
    local args = args or {}
    local width,height=item.width,item.widget.height+10
    local img = cairo.ImageSurface(cairo.Format.ARGB32, width, height)
    local cr = cairo.Context(img)
    cr:set_operator(cairo.Operator.SOURCE)
    cr:set_source_rgba( 1, 1, 1, 1 )
    cr:paint()
    cr:set_source_rgba( 0, 0, 0, 0 )
    if menu.settings.has_decoration ~= false or menu.settings.has_side_deco == true then
        cr:rectangle(0,0, 3, height)
        cr:rectangle(width-3,0, 3, height)
    else
        cr:rectangle(0,0, 1, height)
        cr:rectangle(width-1,0, 1, height)
    end
    if args.no_horizontal ~= true and not (menu.items[1] == item and menu.settings.has_decoration ~= false) then
        cr:rectangle(0,0, width, 1)
    end
    cr:fill()
    item.widget.shape_clip   = img._native
    item.widget.border_color = menu.settings.border_color or beautiful.menu_border_color or beautiful.fg_normal
end

local function getWibox()
--     if #discardedItems > 0 then --TODO good in theory but buggy in practice
--         for k,v in pairs(discardedItems) do
--             local wb = v
--             discardedItems[k] = nil
--             return wb
--         end
--     else
        return wibox({ position = "free", visible = false, ontop = true, menu_border_width = beautiful.menu_border_width or 1, border_color = beautiful.border_normal })
--     end
end

local function stopGrabber(noHide)
    if not noHide then
        currentMenu:hideEverything()
    end
    capi.keygrabber.stop()
    grabKeyboard = false
    currentMenu  = nil return false
end

local function getFilterWidget(aMenu)
    local menu = aMenu or currentMenu or nil
    if menu.settings.showfilter == true then
        if menu.filterWidget == nil then
            local textbox       = wibox.widget.textbox()
            textbox:set_markup(menu.settings.filterprefix)
            local filterWibox   = wibox({ position = "free", visible = false, ontop = true, menu_border_width = beautiful.menu_border_width or 1, border_color = beautiful.border_normal })
            filterWibox:set_bg(beautiful.bg_highlight)
            local l = wibox.layout.fixed.horizontal()
            l:add(textbox)
            filterWibox:set_widget(l)
            filterWibox.visible = true
            menu.filterWidget   = {textbox = textbox, widget = filterWibox, hidden = false, width = menu.settings.itemWidth, height = menu.settings.itemHeight}
            filterWibox:buttons( util.table.join(button({},3,function() menu:toggle(false) end)))
            draw_border(menu,menu.filterWidget,{})
        end
        table.insert(menu.otherwdg,menu.filterWidget)
        return menu.filterWidget
    end
    return nil
end

local function getArrowItem(menu,mode)
    if not menu.topArrow then
        local topA,bottomA = gen_menu_decoration(menu.settings.itemWidth+2,{arrow_x = menu.settings.arrow_x, down = mode == 2, noArrow = mode == 3})
        topA.visible,bottomA.visible = true, true
        menu.topArrow = {widget = topA, hidden = false, width = menu.settings.itemWidth+2, height = topA.height}
        table.insert(menu.otherwdg,menu.topArrow)

        menu.bottomArrow = {widget = bottomA, hidden = false, width = menu.settings.itemWidth+2, height = bottomA.height}
        table.insert(menu.otherwdg,menu.bottomArrow)
    end
    return menu.topArrow,menu.bottomArrow
end

local function getScrollWdg_common(aMenu,widget,step)
    local menu = aMenu or currentMenu or nil
    if menu.settings.maxvisible ~= nil and #menu.items > menu.settings.maxvisible then
        if not menu[widget] then
            local arrow = wibox.widget.imagebox()
            arrow:set_image(beautiful["menu_scrollmenu_".. (widget == "scrollUpWdg" and "up" or "down") .."_icon"])
            local wb = getWibox()
            wb.visible = true
            wb:set_bg(beautiful.bg_highlight)
            wb:buttons( util.table.join(
                        button({ }, 1 , function() menu:scroll( step  ) end),
                        button({ }, 3 , function() menu:toggle( false ) end),
                        button({ }, 4 , function() menu:scroll(   1   ) end),
                        button({ }, 5 , function() menu:scroll(  -1   ) end)
                    ))
            local test2 = wibox.widget.textbox()
            test2:set_text(" ")
--             wb.widgets = {test2,arrow,test2,layout = widget2.layout.horizontal.flexcached}
            local l = wibox.layout.fixed.horizontal()
            local m = wibox.layout.margin(arrow)
            m:set_left(50)
            m:set_right(50)
            l:add(m)
            l:fill_space(true)
            wb:set_widget(l)
            menu[widget] = {widget = wb, hidden = false, width = menu.settings.itemWidth, height = menu.settings.itemHeight}
            draw_border(menu,menu[widget],{})
            wb:connect_signal("mouse::enter", function() wb:set_bg(beautiful.bg_alternate )end)
            wb:connect_signal("mouse::leave", function() wb:set_fg(beautiful.bg_highlight )end)
            table.insert(menu.otherwdg,menu[widget])
        end
        return menu[widget]
    end
    return nil
end

local function getScrollUpWdg(aMenu)
    return getScrollWdg_common(aMenu,"scrollUpWdg",aMenu.downOrUp < 0 and 1 or -1)
end

local function getScrollDownWdg(aMenu)
    return getScrollWdg_common(aMenu,"scrollDownWdg",aMenu.downOrUp < 0 and -1 or 1)
end

local function activateKeyboard(curMenu)
    currentMenu = curMenu or currentMenu or nil
    if not currentMenu or grabKeyboard == true then return end
    if (not currentMenu.settings.nokeyboardnav) and currentMenu.settings.visible == true then
        grabKeyboard = true
        capi.keygrabber.run(function(mod, key, event)
--         print(mod[1],"'"..key.."'",event) --DEBUG
            for k,v in pairs(currentMenu.filterHooks) do --TODO modkeys
                if k.key == "Mod4" and (key == "End" or key == "Super_L") then
                    local found = false
                    for k3,v3 in ipairs(mod) do
                        if v3 == "Mod4" and event == k.event then
                            local retval = v(currentMenu,mod)
                        end
                    end
                end
--                 if #mod == #k.mod then
--                     for k2,v2 in ipairs(k.mod) do
--                         local found = false
--                         for k3,v3 in ipairs(mod) do
--                             if v3 == v2 then found = true end
--                         end
--                         if not found then
--                             stopGrabber()
--                             grabKeyboard = false
--                             return false
--                         end
--                     end
--                 else
--                     stopGrabber()
--                     grabKeyboard = false
--                     return false
--                 end
                if k.key == key and k.event == event then
                    local retval = v(currentMenu,mod)
                    if retval == false then
                        grabKeyboard = false
                    end
                    return retval
                end
            end
            if event == "release" then
                return true
            end

            if (currentMenu.keyShortcut[{mod,key}] or key == 'Return') and currentMenu.items[currentMenu.currentIndex] and currentMenu.items[currentMenu.currentIndex].button1 then
                currentMenu.items[currentMenu.currentIndex].button1()
                currentMenu:toggle(false)
            elseif key == 'Escape' or (key == 'Tab' and currentMenu.filterString == "") then
                stopGrabber()
            elseif (key == 'Up' and currentMenu.downOrUp == 1) or (key == 'Down' and currentMenu.downOrUp == -1) then
                currentMenu:rotate_selected(-1)
            elseif (key == 'Down' and currentMenu.downOrUp == 1) or (key == 'Up' and currentMenu.downOrUp == -1) then
                currentMenu:rotate_selected(1)
            elseif (key == 'BackSpace') and currentMenu.filterString ~= "" and currentMenu.settings.filter == true then
                currentMenu.filterString = currentMenu.filterString:sub(1,-2)
                currentMenu:filter(currentMenu.filterString:lower())
                if getFilterWidget() ~= nil then
                    getFilterWidget().textbox:set_markup(getFilterWidget().textbox._layout.text:sub(1,-2))
                end
            elseif currentMenu.settings.filter == true and key:len() == 1 then
                currentMenu.filterString = currentMenu.filterString .. key:lower()
                local fw = getFilterWidget()
                if fw ~= nil then
                    fw.textbox:set_markup(fw.textbox._layout.text .. key:lower())
                    if currentMenu.settings.autoresize and fw.textbox._layout:get_pixel_extents().width > currentMenu.settings.itemWidth then
                        currentMenu.settings.itemWidth = fw.textbox._layout:get_pixel_extents().width + 40
                        currentMenu.hasChanged = true
                        currentMenu:set_coords()
                    end
                end
                currentMenu:filter(currentMenu.filterString:lower())
            else
                stopGrabber()
            end
            return true
        end)
    end
end

-- Individual menu function
local function new(args)
  local subArrow  = wibox.widget.imagebox()
  subArrow:set_image( beautiful.menu_submenu_icon   )

  local function createMenu(args)
    args          = args or {}
    local menu    = { settings = { 
    -- Settings
    --PROPERTY           VALUE               BACKUP VLAUE         
    itemHeight     = args.itemHeight     or beautiful.menu_height ,
    visible        = false                                        ,
    itemWidth      = args.width          or beautiful.menu_width  ,
    bg_normal      = args.bg_normal      or beautiful.menu_bg or beautiful.bg_normal   ,
    bg_focus       = args.bg_focus       or beautiful.bg_focus    ,
    nokeyboardnav  = args.nokeyboardnav  or false                 ,
    noautohide     = args.noautohide     or false                 ,
    filter         = args.filter         or false                 ,
    showfilter     = args.showfilter     or false                 ,
    maxvisible     = args.maxvisible     or nil                   ,
    filterprefix   = args.filterprefix   or "<b>Filter:</b>"      ,
    autodiscard    = args.autodiscard    or false                 ,
    x              = args.x              or nil                   ,
    y              = args.y              or nil                   ,
    arrow_x        = args.arrow_x        or nil                   ,
    has_decoration = args.has_decoration --[[or true]]            ,
    has_side_deco  = args.has_side_deco  --[[or true]]            ,
    autoresize     = args.autoresize     or false                 ,
    filtersubmenu  = args.filtersubmenu  or false                 ,
    noarrow        = args.noarrow        or false
    },-------------------------------------------------------------

    -- Data
    --  TYPE      INITIAL VALUE                                  
    signalList    = {}                                          ,
    items         = {}                                          ,
    hasChanged    = nil                                         ,
    highlighted   = {}                                          ,
    currentIndex  = 1                                           ,
    keyShortcut   = {}                                          ,
    filterString  = ""                                          ,
    filterWidget  = nil                                         ,
    scrollUpWdg   = nil                                         ,
    scrollDownWdg = nil                                         ,
    otherwdg      = {}                                          ,
    filterHooks   = {}                                          ,
    downOrUp      = 1                                           ,
    startat       = 1                                           ,
    -------------------------------------------------------------
    }

    function menu:toggle(value)
      if menu.need_sub_cleanup and (value or not self.settings.visible) == false then
          for k2,v2 in next, self.items do
              if type(v2.subMenu) == "table" then
                  for k, v in next, v2.subMenu.items do
                      v.widget.visible = false
                  end
              end
          end
          menu.need_sub_cleanup = false
      end
      if self.settings.visible == false and value == false then return 0 end

      self.settings.visible = value or not self.settings.visible
      if self.settings.visible == false then
        self:toggle_sub_menu(nil,true,false)
        local w = getFilterWidget(self)
        if w and menu.filterString ~= "" then
            w.textbox:set_markup(menu.settings.filterprefix)
            menu.filterString = ""
            menu:filter("",nil,true)
--             w.wdg.visible = true
        end
      end

      if menu.settings.maxvisible ~= nil and #menu.items > menu.settings.maxvisible then
          menu:scroll(0,true)
      end

      for v, i in next, self.items do
        if type(i) ~= "function" and type(v) == "number" then
          if i.is_embeded_menu then
            i:toggle(self.settings.visible and not i.hidden and not i.off)
          else
            i.widget.visible = self.settings.visible and not i.hidden and not i.off
          end
        end
      end

      self:emit((self.settings.visible == true) and "menu::show" or "menu::hide")

      for v, i in next, self.otherwdg do
          if i.widget then
            i.widget.visible = self.settings.visible
          end
      end

      if not self.settings.parent then
        activateKeyboard(self)
      end
      local toReturn = self:set_coords()

      if self.settings.autodiscard == true and self.settings.visible == false then
          self:discard()
      end
      return toReturn
    end

    function menu:discard()
      for v, i in next, self.items do
          i:discard()
      end
      for v, i in next, self.otherwdg do
          --table.insert(discardedItems,i.widget) --TODO LEAK
      end
    end

    function menu:clear()
        local v = self.settings.visible
        self.items = {}
        menu:toggle(false)
        if v == true then
            self:toggle(true)
        end
        if menu.settings.parent and menu.settings.parent.settings.visible then
            menu.settings.parent:toggle(true)
        end
    end

    function menu:scroll(step,notoggle)
        menu.startat = menu.startat + step
        if menu.startat < 1 then
            menu.startat = 1
        elseif menu.startat > #menu.items - (menu.settings.maxvisible or 999999) then
            menu.startat = #menu.items - (menu.settings.maxvisible or 999999)
        end
        local counter = 1
        for v, i in next, self.items do
            local tmp = i.off
            i.off = ((counter < menu.startat) or (counter - menu.startat > (menu.settings.maxvisible or 999999)))
            if not tmp == i.off then self.hasChanged = true end
            counter = counter +1
        end
        if not notoggle then menu:toggle(true) end
    end

    function menu:rotate_selected(leap)
        if self.currentIndex + leap > #self.items then
            self.currentIndex = 1
        elseif self.currentIndex + leap < 1 then
            self.currentIndex = #self.items
        else
            self.currentIndex = self.currentIndex + leap
        end
        if self.items[self.currentIndex].hidden == true or self.items[self.currentIndex].off == true then
            self:rotate_selected((leap > 0) and 1 or -1)
        end
        self:clear_highlight()
        self:highlight_item(self.currentIndex) 
        return self.items[self.currentIndex]
    end

    function menu:emit(signName)
        for k,v in pairs(self.signalList[signName] or {}) do
            v(self)
        end
    end

    function menu:highlight_item(index)
        if self.items[index] ~= nil then
            if self.items[index].widget ~= nil then
                self.items[index]:hightlight(true)
            end
        end
    end

    function menu:clear_highlight()
        if #(self.highlighted) > 0 then
            for k, v in pairs(self.highlighted) do
                v:hightlight(false)
            end
            self.highlighted = {}
        end
    end

    local filterDefault = function(item,text)
        if item.text:lower():find(text) ~= nil then
            return false
        end
        return true
    end

    function menu:filter(text,func,nocat)
        local toExec = func or filterDefault
        for k, v in next, self.items do
            if v.nofilter == false then
                local hidden = toExec(v,text)
                self.hasChanged = self.hasChanged or (hidden ~= v.hidden)
                v.hidden = hidden
            end
        end
        if not nocat and self.settings.filtersubmenu then
            self.items_sub = {}
            for k2,v2 in next, self.items do
                if type(v2.subMenu) == "table" then
                    for k, v in next, v2.subMenu.items do
                        if v.nofilter == false then
                            local hidden = toExec(v,text)
                            self.hasChanged = self.hasChanged or (hidden ~= v.hidden)
                            if hidden == false then
                                self.items_sub[#self.items_sub+1] = v
                                v.widget.visible = true
                                menu.need_sub_cleanup = true
                                v2.subMenu.hasChanged = true
                            else
                                v.widget.visible = false
                            end
                        end
                    end
                end
            end
        end
        self:toggle(self.settings.visible)
    end

    function menu:set_coords(x,y)
        local prevX = self.settings["xPos"] or -1
        local prevY = self.settings["yPos"] or -1

        self.settings.xPos = x or self.settings.x or prevent_toolbar_overlap("x","width")
        self.settings.yPos = y or self.settings.y or prevent_toolbar_overlap("y","height")

        if prevX ~= self.settings["xPos"] or prevY ~= self.settings["yPos"] then
            self.hasChanged = true
        end

        if self.settings.visible == false or self.hasChanged == false then
            return 0
        end

        if self.hasChanged == true then
            self:emit("menu::changed")
        end

        self.hasChanged = false

        local yPadding = 0
        if #self.items*self.settings.itemHeight + self.settings["yPos"] > capi.screen[capi.mouse.screen].geometry.height and not self.forceDownOrUp then
            self.downOrUp = -1
            yPadding = -self.settings.itemHeight
        end
        local function set_geometry(wdg)
            if not wdg then return end
            if wdg.is_embeded_menu == true then
                wdg.settings.x = self.settings.xPos
                wdg.settings.y = self.settings.yPos+yPadding
                wdg.downOrUp = menu.downOrUp
                wdg.forceDownOrUp = true
                wdg.hasChanged = true
                yPadding = yPadding + wdg:toggle(true)
            end
            if type(wdg) ~= "function" and wdg.hidden == false and not (wdg.subMenu and type(wdg.subMenu) == "table" and #wdg.subMenu.items == 0) and wdg.off ~= true then
                local geo = wdg.widget:geometry()
                wdg.x = self.settings.xPos
                wdg.y = self.settings.yPos+yPadding
                if wdg.widget.x ~= wdg.x or wdg.widget.y ~= wdg.y or wdg.widget.width ~= wdg.width or wdg.widget.height ~= wdg.height or (menu.settings.autoresize and self.settings.itemWidth ~= wdg.widget.width) then
                    wdg.widget.x = wdg.x
                    wdg.widget.y = wdg.y
                    wdg.widget.height = wdg.height
                    if menu.settings.autoresize then
                        wdg.width = self.settings.itemWidth
                    end
                    local width_changed = wdg.widget.width ~= wdg.width
                    wdg.widget.width = wdg.width
                    if width_changed then
                        draw_border(self,wdg)
                    end
                end
                yPadding = yPadding + (wdg.height or self.settings.itemHeight)*self.downOrUp
                if type(wdg.subMenu) ~= "function" and wdg.subMenu ~= nil and wdg.subMenu.settings ~= nil then
                    wdg.subMenu.settings.x = wdg.x+wdg.width
                    wdg.subMenu.settings.y = wdg.y
                end
            end
      end

      local function addWdg(tbl,order)
        for i=(order == -1) and #tbl or 1, (order == -1) and 1 or #tbl, order do
            set_geometry(tbl[i])
        end
      end

      local arrowMode
      if not self.settings.noarrow then
        if menu.settings.parent then
            arrowMode = 3
            if self.settings.yPos - 10 > 0 and not self.is_embeded_menu then
                self.settings.yPos = self.settings.yPos - (self.settings.has_decoration ~= false and 10 or 0)
            end
            if self.downOrUp < 0 then
                self.settings.yPos = self.settings.yPos + (self.items[1] and self.items[1].height or 0)
            end
        elseif self.downOrUp == 1  then
            arrowMode = 1
        else
            arrowMode = 2
        end
      end

      if menu.settings.has_decoration ~= false then
          getArrowItem(menu,self.settings.noarrow and 3 or arrowMode)
      end
      local headerWdg,footerWdg = {self.topArrow,getScrollUpWdg(self)},{getFilterWidget(self),self.bottomArrow}
      if getScrollDownWdg(self) then
          table.insert(footerWdg,1,getScrollDownWdg(self))
      end

      addWdg((self.downOrUp == -1) and footerWdg or headerWdg,self.downOrUp)
      for v, i in next, self.items do
        set_geometry(i)
      end
      if self.items_sub then
        for v, i in next, self.items_sub do
            set_geometry(i)
        end
      end
      addWdg((self.downOrUp == 1) and footerWdg or headerWdg,self.downOrUp)

      return yPadding or 100
    end

    function menu:set_width(width)
        self.settings.itemWidth = width
    end

    ---Possible signals = "menu::hide", "menu::show", "menu::resize"
    function menu:add_signal(name,func)
        self.signalList[name] = self.signalList[name] or {}
        table.insert(self.signalList[name],func)
    end

    function menu:add_key_hook(mod, key, event, func)
        if key and event and func then
            --table.insert(filterHooks,{, func = func})
            self.filterHooks[{key = key, event = event, mod = mod}] = func
        end
    end

    function menu:toggle_sub_menu(aSubMenu,hideOld,forceValue) --TODO dead code?
      if (self.subMenu ~= nil) and (hideOld == true) then
        self.subMenu:toggle_sub_menu(nil,true,false)
        self.subMenu:toggle(false)
      end

      if aSubMenu ~= nil and aSubMenu.toggle ~= nil then
        aSubMenu:toggle(forceValue or true)
      end
      self.subMenu = aSubMenu
    end

    function menu:hideEverything()
        menu:toggle(false)
        local aMenu = menu.settings.parent
        while aMenu ~= nil do
          aMenu:toggle(false)
          aMenu = aMenu.settings.parent
        end
        if currentMenu == menu then
            stopGrabber(true)
        end
      end

      local function clickCommon(data, index)
          if data["button"..index] ~= nil then
              data["button"..index](menu,data)
          end
          if menu.settings.noautohide == false and index ~= 4 and index ~= 5 then
              menu:hideEverything()
          elseif menu.settings.maxvisible and index == 4 and #menu.items > menu.settings.maxvisible then
              menu:scroll((menu.downOrUp > 0) and -1 or 1)
          elseif menu.settings.maxvisible and index == 5 and #menu.items > menu.settings.maxvisible then
              menu:scroll((menu.downOrUp > 0) and 1 or -1)
          end
      end

      local function registerButton(aWibox,data)
        aWibox:buttons( util.table.join(
            button({ }, 1 , function() clickCommon(data,1 ) end),
            button({ }, 2 , function() clickCommon(data,2 ) end),
            button({ }, 3 , function() clickCommon(data,3 ) end),
            button({ }, 4 , function() clickCommon(data,4 ) end),
            button({ }, 5 , function() clickCommon(data,5 ) end),
            button({ }, 6 , function() clickCommon(data,6 ) end),
            button({ }, 7 , function() clickCommon(data,7 ) end),
            button({ }, 8 , function() clickCommon(data,8 ) end),
            button({ }, 9 , function() clickCommon(data,9 ) end),
            button({ }, 10, function() clickCommon(data,10) end)
        ))
      end

    function menu:add_item(args)
      local aWibox = getWibox()
      local data = {
        --PROPERTY       VALUE                BACKUP VALUE          
        text        = args.text        or ""                       ,
        hidden      = args.hidden      or false                    ,
        off         = false            or nil                      ,
        prefix      = args.prefix      or nil                      ,
        suffix      = args.suffix      or nil                      ,
        align       = args.align       or "left"                   ,
        prefixwidth = args.prefixwidth or nil                      ,
        suffixwidth = args.suffixwidth or nil                      ,
        prefixbg    = args.prefixbg    or nil                      ,
        suffixbg    = args.suffixbg    or nil                      ,
        width       = args.width       or self.settings.itemWidth  ,
        height      = args.height      or self.settings.itemHeight ,
        widget      = aWibox           or nil                      ,
        icon        = args.icon        or nil                      ,
        checked     = args.checked     or nil                      ,
        button1     = args.onclick     or args.button1             ,
        onmouseover = args.onmouseover or nil                      ,
        onmouseout  = args.onmouseout  or nil                      ,
        subMenu     = args.subMenu     or nil                      ,
        nohighlight = args.nohighlight or false                    ,
        noautohide  = args.noautohide  or false                    ,
        addwidgets  = args.addwidgets  or nil                      ,
        nofilter    = args.nofilter    or false                    ,
        bg          = args.bg          or beautiful.menu_bg or beautiful.bg_normal      ,
        fg          = args.fg          or beautiful.fg_normal      ,
        x           = 0                                            ,
        y           = 0                                            ,
        widgets     = {}                                           ,
        pMenu       = self                                         ,
        ------------------------------------------------------------
      }
      for i=2, 10 do
          data["button"..i] = args["button"..i]
      end
      data.pMenu.hasChanged = true

      table.insert(data.pMenu.items, data)
      local pos = #data.pMenu.items
      data.pMenu:set_coords() --TODO needed?

      --Member functions
      function data:check(value)
          self.checked = (value == nil) and self.checked or ((value == false) and false or value)
          if self.checked == nil then return end
          self.widgets.checkbox = self.widgets.checkbox or wibox.widget.imagebox()
          self.widgets.checkbox.image = (self.checked == true) and checkbox.checked() or checkbox.unchecked() or nil
          self.widgets.checkbox.bg = beautiful.bg_focus
      end

      function data:hightlight(value)
          if not self.widget or value == nil then return end

          self.widget:set_bg(((value == true) and menu.settings.bg_focus or data.bg) or "")
          if value == true then
              table.insert(menu.highlighted,self)
          end
      end

      function data:discard()
          table.insert(discardedItems,aWibox)
      end

      if data.subMenu ~= nil then
         subArrow2 = subArrow
         if type(data.subMenu) ~= "function" and data.subMenu.settings then
           data.subMenu.settings.parent = data.pMenu
         end
      else
        subArrow2 = nil
      end

      local function toggleItem(value)
          if data.nohighlight ~= true then
              data:hightlight(value)
          end
          if value == true then
            currentMenu = data.pMenu
            data.pMenu.currentIndex = pos
            if type(data.subMenu) ~= "function" then
              data.pMenu:toggle_sub_menu(data.subMenu,value,value)
            elseif data.subMenu ~= nil then
              local aSubMenu = data.subMenu()
              if not aSubMenu then return end
              aSubMenu.settings.x = data.x + aSubMenu.settings.itemWidth
              aSubMenu.settings.y = data.y
              aSubMenu.settings.parent = data.pMenu
              data.pMenu:toggle_sub_menu(aSubMenu,value,value)
            end
          end
      end

      local optionalWdgFeild = {"width","bg"}
      local function createWidget(field,type2)
        local newWdg
        if type2 == "imagebox" then
          newWdg = wibox.widget.imagebox()
        elseif type2 == "textbox" then
             newWdg = wibox.widget.textbox()
        end
--         local newWdg = (data[field] ~= nil) and capi.widget({type=type2 }) or nil
        if newWdg ~= nil and type2 == "textbox" then
            data[field] = string.gsub(data[field] or "", "&", "and")
            newWdg:set_markup(data[field] or "")
        elseif newWdg ~= nil and type2 == "imagebox" and type(data[field]) == "string" then
            newWdg:set_image(data[field])
        elseif newWdg ~= nil and type2 == "imagebox" then
            newWdg:set_image(data[field])
        end

        for k,v in pairs(optionalWdgFeild) do
            if newWdg ~= nil and data[field..v] ~= nil then
                newWdg[v] = data[field..v]
            end
        end
        return newWdg
      end

      data:check()

      data.widgets.prefix = createWidget("prefix", "textbox"  )
      data.widgets.suffix = createWidget("suffix", "textbox"  )
      data.widgets.wdg    = createWidget("text"  , "textbox"  )
      data.widgets.icon   = createWidget("icon"  , "imagebox" )
      local m = wibox.layout.margin(data.widgets.wdg)
      m:set_left(7)
      m:set_right(7)

      aWibox:set_bg(data.bg)
      data.widgets.wdg:set_markup("<span color=\"".. data.fg .."\" >"..(data.widgets.wdg._layout.text or "").."</span>")
      data.widgets.wdg.align = data.align
      local l = wibox.layout.align.horizontal()
      l:set_middle(m)
      local l_l = wibox.layout.fixed.horizontal()
      local l_r = wibox.layout.fixed.horizontal()
      l_l:add(data.widgets.prefix)
      local m = wibox.layout.margin(data.widgets.icon)
      m:set_margins(2)
      l_l:add(m)
      if data.addwidgets then
        l_r:add(data.addwidgets)
      end
      l_r:add(data.widgets.suffix)
      if data.widgets.checkbox then
        l_r:add(data.widgets.checkbox)
      end
      if subArrow2 then
        l_r:add(subArrow2)
      end
      l:set_right(l_r)
      l:set_left(l_l)
--       local bgb = wibox.widget.background()
--       bgb:set_widget(l)
--       data.widgets.bgwdg = bgb
      aWibox:set_widget(l)

      --Check width
      if menu.settings.autoresize then
        local twidth = 0
        for k,v in pairs(data.widgets) do
            if v and v._layout then
                print("HAPPY",v._layout:get_pixel_extents().width,(v.get_width and v:get_width() or "no"),"<span color=\"".. data.fg .."\" >"..(data.widgets.wdg._layout.text or "").."</span>")
                twidth = twidth + v._layout:get_pixel_extents().width
            elseif v and v._image then
                twidth = twidth + v._image:get_width()
            end
        end
        if twidth > self.settings.itemWidth then
            self.settings.itemWidth = twidth + 40
            self.hasChanged = true
        end
      end

      --aWibox.widgets = {{data.widgets.prefix,data.widgets.icon, {subArrow2,data.widgets.checkbox,data.widgets.suffix, layout = widget2.layout.horizontal.rightleft},data.addwidgets, layout = widget2.layout.horizontal.leftright,{data.widgets.wdg, layout = widget2.layout.horizontal.flex}}, layout = widget2.layout.vertical.flex }
--       aWibox.widgets = {{data.widgets.prefix,data.widgets.icon,data.widgets.wdg, {subArrow2,data.widgets.checkbox,data.widgets.suffix, layout = widget2.layout.horizontal.rightleftcached},data.addwidgets, layout = widget2.layout.horizontal.leftrightcached}, layout = widget2.layout.vertical.flexcached }

      registerButton(aWibox, data)

      aWibox:connect_signal("mouse::enter", function() toggleItem(true) end)
      aWibox:connect_signal("mouse::leave", function() toggleItem(false) end)
      aWibox.visible = false
      draw_border(menu,data,{})
      if menu.settings.parent and menu.is_embeded_menu then
          menu.settings.parent.hasChanged = true
      end
      return data
    end

    function menu:add_existing_item(item)
        if not item then return end
        item.pMenu = menu
        registerButton(item.widget,item)
        self.items[#self.items+1] = item
        if menu.settings.parent and menu.is_embeded_menu then
            menu.settings.parent.hasChanged = true
        end
    end

    function menu:add_wibox(wibox,args)
        local args = args or {}
        local data     = {
            widget     = wibox,
            hidden     = false,
            width      = args.width      or self.settings.itemWidth  , 
            height     = args.height     or self.settings.itemHeight , 
            button1    = args.onclick    or args.button1             ,
            noautohide = args.noautohide or false                    ,
        }
        for i=2, 10 do
            data["button"..i] = args["button"..i]
        end

        function data:hightlight(value) end
        draw_border(menu,data,{no_horizontal=false})
        registerButton(wibox,data)
        wibox:connect_signal("mouse::enter", function() currentMenu = self end)
        table.insert(self.items, data)
        self.hasChanged = true
        if menu.settings.parent and menu.is_embeded_menu then
            menu.settings.parent.hasChanged = true
        end
    end

    function menu:add_embeded_menu(m2,args)
        m2.is_embeded_menu = true
        m2.settings.parent = self
        table.insert(self.items, m2)
    end

--     function menu:add_wibox(m,args)
--        m.isMenu = true
--     end

    return menu
  end

  return createMenu(args)
end

function gen_menu_decoration(width,args)
    local args = args or {}
    local w,w2 = wibox({position="free",visible=false,bg=beautiful.menu_bg}), wibox({position="free",viaible=false,bg=beautiful.menu_bg})
    w.width,w2.width=width,width
    w.height,w2.height = (not args.down and not args.noArrow) and 23 or 10, (not args.down or args.noArrow) and 10 or 23
    w.ontop,w2.ontop = true,true
    w.visible,w2.visible = false,false
    w.border_color,w2.border_color = beautiful.menu_border_color or beautiful.fg_normal,beautiful.menu_border_color or beautiful.fg_normal
    local function do_gen_menu_top(width, radius,padding)
        local img = cairo.ImageSurface(cairo.Format.ARGB32, width,23)
        local cr = cairo.Context(img)
        cr:set_operator(cairo.Operator.SOURCE)
--         cr:set_antialias(1)
        cr:set_source_rgba( 1, 1, 1, 1 )
        cr:paint()
        cr:set_source_rgba( 0, 0, 0, 0 )
        if not args.down then
            cr:rectangle((args.arrow_x or 20)+20+6, 0, width-(args.arrow_x or 20)+20, 13 + (padding or 0), true, "#ffffff")
            cr:rectangle(padding or 0,0, (args.arrow_x or 20), 13 + (padding or 0), true, "#ffffff")
            cr:rectangle((args.arrow_x or 20),0,3, 13+ (padding or 0), true, "#ffffff")
        else
            cr:rectangle((args.arrow_x or 20)+20+6, 10-(padding or 0), width-(args.arrow_x or 20)+20, 13 - (padding or 0), true, "#ffffff")
            cr:rectangle(padding or 0,10-(padding or 0), 20, 13 - (padding or 0), true, "#ffffff")
        end
        for i=0,(13) do
            if not args.down then
                cr:rectangle((args.arrow_x or 20)+i+3   , padding or 0         , 1, 13-i, true, "#ffffff")
                cr:rectangle((args.arrow_x or 20)+20+6-i, padding or 0         , 1, 13-i, true, "#ffffff")
            else
                cr:rectangle((args.arrow_x or 20)+13+i  , 26-3-i-(padding or 0), 1, i   , true, "#ffffff")
                cr:rectangle((args.arrow_x or 20)+13-i  , 26-3-i-(padding or 0), 1, i   , true, "#ffffff")
            end
        end
        cr:rectangle (0 , (not args.down) and 13 or 0 , radius + (padding or 0), radius + (padding or 0), true, "#ffffff")
        cr:rectangle (width-10 + (padding or 0), (not args.down) and 13 or 0 + (padding or 0) , radius, radius, true, "#ffffff")
        cr:fill()
--         cr:draw_circle    (10, (not args.down) and 23+1 or 0, radius - ((not args.down) and 0 or 1), radius  - ((not args.down) and 0 or 1), true, "#000000")
        cr:set_source_rgba( 1, 1, 1, 1 )
        cr:arc(10,(not args.down) and 23 or 0,radius- ((not args.down) and 0 or 1),0,2*math.pi)
--         cr:draw_circle(width-10 + (padding or 0), ((not args.down) and (23+1) or 0) + (pdding or 0), radius- ((not args.down) and 0 or 1), radius- ((not args.down) and 0 or 1), true, "#000000"
        cr:arc(width-10 + (padding or 0), ((not args.down) and (23) or 0) + (pdding or 0),radius- ((not args.down) and 0 or 1),0,2*math.pi)
        cr:fill()
        return img
    end
    local function do_gen_menu_bottom(width,radius,padding,down)
        local img5 = cairo.ImageSurface(cairo.Format.ARGB32, width,10)
        local cr = cairo.Context(img5)
        cr:set_operator(cairo.Operator.SOURCE)
--         cr:set_antialias(1)
        cr:set_source_rgba( 1, 1, 1, 1 )
        cr:paint()
        cr:set_source_rgba( 0, 0, 0, 0 )
        cr:rectangle(0,not down and radius or 0, width, padding or 0)
        cr:rectangle(0,0, radius + (padding or 0), radius + (padding or 0))
        cr:rectangle(width-10,0, radius + (padding or 0), radius + (padding or 0))
        cr:fill()
        cr:set_source_rgba( 1, 1, 1, 1 )
        cr:arc(10,down and 10 or 0,radius,0,2*math.pi)
        cr:arc(width-10,down and 10 or 0,radius,0,2*math.pi)
        cr:fill()
        return img5
    end
    w.shape_clip      = ((not args.down and not args.noArrow) and do_gen_menu_top(width-(3),7,3)    or do_gen_menu_bottom(width,7,3,true))._native
    w.shape_bounding  = ((not args.down and not args.noArrow) and do_gen_menu_top(width,10,0)       or do_gen_menu_bottom(width,10,0,true))._native
    w2.shape_clip     = ((not args.down or   args.noArrow) and do_gen_menu_bottom(width,7,3,false)  or do_gen_menu_top(width-(3),7,3))._native
    w2.shape_bounding = ((not args.down or   args.noArrow) and do_gen_menu_bottom(width,10,0,false) or do_gen_menu_top(width,10,0))._native
    return w,w2
end

return setmetatable(module, { __call = function(_, ...) return new(...) end })
