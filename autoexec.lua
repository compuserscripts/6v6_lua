
--autoexec.lua
--place in C:\Users\%username%\AppData\Local
local path = os.getenv('localappdata')
LoadScript(path .. [[\ammo.lua ]])
LoadScript(path .. [[\anti_air.lua ]])
LoadScript(path .. [[\esp.lua ]])
LoadScript(path .. [[\pylon.lua ]])
LoadScript(path .. [[\sticky.lua ]])
LoadScript(path .. [[\trails.lua ]])
--LoadScript(path .. [[\uber.lua ]])
LoadScript(path .. [[\uber2.lua ]])
LoadScript(path .. [[\hiders.lua ]])
LoadScript(path .. [[\focusfire.lua ]])
--LoadScript(path .. [[\arrow.lua ]])
--LoadScript(path .. [[\spectate.lua ]])
--disabled due to potential fps drain. counterproductive in comp lol
--LoadScript(path .. [[\nohats.lua ]])
LoadScript(path .. [[\beam.lua ]])
--LoadScript(path .. [[\jumptrajectory.lua ]])
LoadScript(path .. [[\critheals.lua ]])
LoadScript(path .. [[\sentryline.lua ]])
--LoadScript(path .. [[\preventuncloak.lua ]])
--LoadScript(path .. [[\stickycam.lua ]])
--LoadScript(path .. [[\chatbubbles.lua ]])
--LoadScript(path .. [[\red_det_now_lite.lua ]])
--disabled due to zoom sensitivity ratio calculation being detectable (rapidly changing value) i see no reason to use the script without it
--LoadScript(path .. [[\betterscope.lua ]])
--not ready for general use
--LoadScript(path .. [[\pipepredict.lua ]])
LoadScript(path .. [[\enemycam.lua ]])

callbacks.Register("Unload", function()
    UnloadScript(path .. [[\ammo.lua ]])
    UnloadScript(path .. [[\anti_air.lua ]])
    UnloadScript(path .. [[\esp.lua ]])
    UnloadScript(path .. [[\pylon.lua ]])
    UnloadScript(path .. [[\sticky.lua ]])
    UnloadScript(path .. [[\trails.lua ]])
    UnloadScript(path .. [[\uber.lua ]])
    UnloadScript(path .. [[\hiders.lua ]])
    UnloadScript(path .. [[\focusfire.lua ]])
    UnloadScript(path .. [[\arrow.lua ]])
    UnloadScript(path .. [[\spectate.lua ]])
    UnloadScript(path .. [[\nohats.lua ]])
    UnloadScript(path .. [[\beam.lua ]])
    UnloadScript(path .. [[\jumptrajectory.lua ]])
    UnloadScript(path .. [[\critheals.lua ]])
    UnloadScript(path .. [[\sentryline.lua ]])
    UnloadScript(path .. [[\preventuncloak.lua ]])
    UnloadScript(path .. [[\stickycam.lua ]])
    UnloadScript(path .. [[\chatbubbles.lua ]])
    UnloadScript(path .. [[\betterscope.lua ]])
    UnloadScript(path .. [[\pipepredict.lua ]])
end)
