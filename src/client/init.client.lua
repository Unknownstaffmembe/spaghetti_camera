local camera_module = require(script:WaitForChild("camera_module"))
local Camera = workspace.CurrentCamera
local ForwardVector = Vector3.new(0, 0, 1)
local BottomLeftPosition = Vector3.new(0, 10, 0)

Camera:GetPropertyChangedSignal("CameraType"):Connect(function()
	Camera.CameraType = "Scriptable"
end)

Camera.CameraType = "Scriptable"
print("Starting")
camera_module.StartPanning(Camera, 100, 100, 100, 50, 50, 100, ForwardVector, BottomLeftPosition)
