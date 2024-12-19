DOWNLOAD >> https://github.com/compuserscripts/6v6_lua/archive/refs/heads/main.zip

Extract to `C:\Users\%username%\AppData\Local` (WinKey + R)

autoexec.lua will automatically load all scripts specified in the file


-------------------------------



TODO;

ubercounter modification - ignoring kritz - calculate fake uber in place for kritz when enabled - make it possible to customize everything easily, position, text size etc etc etc
option to add slight randomness to uber percentage

CRITHEAL INDICATOR, on player and for medic for all players

indicator when to det when people are near stickies

cloak and dagger stop

killfeed colors for different classes. only for enemy

sentry radius, bubble, through walls

esp lasso - same as anti air but for all classes, able to specify different color boxes and tracers for each class. maybe alpha based on distance? also only visible mode for all of them

matchhud enemy hp

prevent shooting/mouse1 if health low enough to explode from rocket if soldier - only if lookling at a wall. Also make it so that if in the face of a player and low health we negate expld dmg by activating jump before shooting - millisecond delay too so its random

indicator where rocket/grenade will land - with seconds remaining

autosap

spy detector, if within certain radius change color to rainbow or something to indicate they decloaked, but only if within certain radius

fix med arrow line to go from eyeangles to where its fired to instead of legs

fix nohats lag -- only draw textures on players who are visible

sentry aim line, like sniper. aDD notif on screen if on you and highlitght sentry or chams. same with sniper

notif on screen if someone looks at you, highlight or borders

sticky explosion radius/rocket explosion radius when drawing projected path, like a ball

fix nohats so that

local get_materials = function(material)
    if material:GetTextureGroupName() == "World textures" then
        --material:ColorModulate(255, 0, 0); --done this one first then done the one below to try "reset" it.
        material:ColorModulate(255, 255, 255);
    end
end
materials.Enumerate(get_materials)

world textures don't get hidden, i guess vertexlitgeneric somethign fucks up
it also lags because of the movechild thing

sentry chams visible only or not if in given radius

C:\Users\User\AppData\Local\arrow.lua :316: attempt to index a nil value (local 'patient')


