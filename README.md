DOWNLOAD >> https://github.com/compuserscripts/6v6_lua/archive/refs/heads/main.zip

Extract to `C:\Users\%username%\AppData\Local` (WinKey + R)

autoexec.lua will automatically load all scripts specified in the file


-------------------------------



TODO;

ubercounter modification - ignoring kritz - calculate fake uber in place for kritz when enabled - make it possible to customize everything easily, position, text size etc etc etc
option to add slight randomness to uber percentage

indicator when to det when people are near stickies

cloak and dagger stop

killfeed colors for different classes. only for enemy

esp lasso - same as anti air but for all classes, able to specify different color boxes and tracers for each class. maybe alpha based on distance? also only visible mode for all of them

matchhud enemy hp

prevent shooting/mouse1 if health low enough to explode from rocket if soldier - only if lookling at a wall. Also make it so that if in the face of a player and low health we negate expld dmg by activating jump before shooting - millisecond delay too so its random

indicator where rocket/grenade will land - with seconds remaining

autosap

spy detector, if within certain radius change color to rainbow or something to indicate they decloaked, but only if within certain radius

fix med arrow line to go from eyeangles to where its fired to instead of legs

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

sniper chams when visible

focusfire/antiair box corners scale with distance

visible box color for focusfire like in antiair

proper unload and register for all scripts

when drawing chams in focusfire/antiair use getmovechild and peer to color the entire model/weapon so all attachments

sniper rendertarget scope, so we can zoom further without using real fov because thats detectable. draw black lines so we can aim too.  make scrollable

make players we aim at fullbright

modified projectile camera, make it not show flying stickies but instead if the last sticky we shot is stationary AND it has line of sight to a player, we display the window and display the camera from the perspective of the sticky, in first person and it will lock on to and follow the nearest person it has line of sight to in first person, from stickys perspective. kind of like a security camera. 

show taunter through walls chams
