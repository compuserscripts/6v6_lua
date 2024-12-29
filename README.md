DOWNLOAD >> https://github.com/compuserscripts/6v6_lua/archive/refs/heads/main.zip

Extract to `C:\Users\%username%\AppData\Local` (WinKey + R)

autoexec.lua will automatically load all scripts specified in the file


-------------------------------



TODO;

ubercounter modification - ignoring kritz - calculate fake uber in place for kritz when enabled - make it possible to customize everything easily, position, text size etc etc etc
option to add slight randomness to uber percentage

indicator when to det when people are near stickies

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

sniper chams when visible

focusfire/antiair box corners scale with distance

visible box color for focusfire like in antiair

proper unload and register for all scripts

when drawing chams in focusfire/antiair use getmovechild and peer to color the entire model/weapon so all attachments

make players we aim at fullbright


show taunter through walls chams

destroy window when player dies

scout scattergun meatshot triggerbot https://github.com/OthmanAba/TeamFortress2/blob/1b81dded673d49adebf4d0958e52236ecc28a956/tf2_src/game/shared/tf/tf_fx_shared.cpp#L22

auto wallbug

wallssticking will not work on walls parallel to x and y axiis

15 30 and 45 degrees, they are not aligned with the x and y axiis you can stick to them just fine.

if you launch yourself towards a wall and quickly tap your left and right movement keys while against wall you can get stuck to it

to hold your position, juts hold whatever key it is that got you stuck


stickycam boolean followLatest - follow latest sticky

boolean autoSwitchClosest - automatically switch to closest sticky

spectaet script - only apply invisible chams if in first person

sticky radius script



medic heal cam - either for medic themself or any player on the team
toggle between enemy and friendly med

remote viewing CIA gangstalk cam - target specific player displaying the world through their eyes in a camera window

will display the vision of teammate being healed in a window

small update/notification library - if present we load it and auto update scripts and display notifications

menu for configuring everything>
