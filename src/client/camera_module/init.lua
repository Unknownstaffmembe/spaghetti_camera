-- Module Table --
local module = {}

----- Loaded Services & Modules -----
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

----- Private Variables -----
-- Events
local Heartbeat = RunService.Heartbeat

-- Constants
local CFrame90Y = CFrame.Angles(0, math.pi/2, 0)
local CFrame90X = CFrame.Angles(-math.pi/2, 0, 0)
local ZeroVector = Vector3.new(0, 0, 0)

-- Screen gui
local ScreenGui = Instance.new("ScreenGui")
local SizePixelsXY

-- Camera
local Camera
local CurrentCFrame

-- Height (measured in studs)
local Height = 100
local ZoomTime = 1
local ZoomGoalJump = 1 -- this will be multiplied by 0.5 with a sign so, this is actually one stud
local ZoomEasingStyle = Enum.EasingStyle.Quad
local ZoomEasingDirection = Enum.EasingDirection.Out
local CurrentZoom
local ZoomIn
local ZoomGoal
local ZoomAlpha

-- Speed (measured in studs per second)
local MinSpeed = 10
local MaxSpeed = 20
local SpeedEasingStyle = Enum.EasingStyle.Quad
local SpeedEasingDirection = Enum.EasingDirection.In
local TimeToReachMaxSpeed = 5
local PositionCalculationCFrame -- Will be used to calculate the position of the camera
local OrientationCalculationCFrame
local ForwardVector
local RightVector
local CurrentMovementVector
local CurrentMovementUnitVector
local MaxX, MaxZ
local X, Z
local NormalisedX, NormalisedZ
local SubNormalisedVector -- The vector isn't normalised but, each component is

local MovementVectorTable = {
	[Enum.KeyCode.W] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.S] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.D] = Vector3.new(1, 0, 0),
}
-- Bézier curve nodes (for a "unit" Bézier curve which will be used to obtain the orientation)
local B1 = Vector2.new(0, 2)
local B2 = Vector2.new(math.sin(math.deg(60)), 0)
local B3 = Vector2.new(1, 0)
local V1 = B1 - B2 -- Vectors (will be used to get some position values which will be used to work out some angle which will be used for the orientation)
local V2 = B3 - B2

-- Connections
local ScrollMouseWheelConnection
local ScrollPinchConnection
local UpdateCameraConnection
local UpdateCameraPositionConnection
local UpdateCameraZoomConnection
local InputBeganConnection
local InputEndedConnection

---- Private Functions ----
local function GetOrientation(Alpha) -- Alpha = normalised value, e.g. if your max height was 10 studs and your current height is 5 studs, your alpha would be 5/10 (0.5), it's 0.5 * the max height
	Alpha = TweenService:GetValue(Alpha, ZoomEasingStyle, ZoomEasingDirection)
	local P1 = Alpha * V1
	local P2 = (1 - Alpha) * V2
	local VP1P2 = P2 - P1 -- Vector P1 to P2
	VP1P2 = VP1P2.Unit -- If VP1P2 is a unit vector, this can be commented out
	return math.atan(VP1P2.Y/VP1P2.X)
end

local function GetSpeed(Time)
	return TweenService:GetValue(math.clamp(Time/TimeToReachMaxSpeed, 0, 1), SpeedEasingStyle, SpeedEasingDirection)
end

local function UpdateCameraCFrame()
	CurrentCFrame = CFrame.Angles(GetOrientation(ZoomAlpha), 0, 0) + (PositionCalculationCFrame * Vector3.new(NormalisedX, ZoomAlpha, NormalisedZ)) 
	Camera.CFrame = CurrentCFrame
end

local StartMovement
local CurrentMovement
local ZoomElapsedTime
local Zooming
local ZoomStart
local DeltaZoom
local function UpdateZoom(DeltaTime)
	if StartMovement ~= CurrentMovement then
		DeltaZoom = 0
		UpdateCameraZoomConnection:Disconnect()	
		Zooming = false
		return
	end
	ZoomElapsedTime += DeltaTime
	if ZoomElapsedTime > ZoomTime then
		CurrentZoom = math.clamp(ZoomStart + DeltaZoom,	0, Height)
		DeltaZoom = 0
		UpdateCameraZoomConnection:Disconnect()	
		Zooming = false
		return
	end
	CurrentZoom = math.clamp(ZoomStart + (ZoomElapsedTime/ZoomTime) * DeltaZoom, 0, Height)
	ZoomAlpha = 1 - CurrentZoom/Height
end

local function UpdateZoomPointerAction(Zoom, _, _, GameProcessedEvent)
	if GameProcessedEvent then return end
	local Movement = (Zoom > 0)
	if Zooming then
		DeltaZoom += ZoomGoalJump * Zoom
		CurrentMovement = Movement
	else
		StartMovement = Movement
		CurrentMovement = Movement
		ZoomStart = CurrentZoom
		DeltaZoom = ZoomGoalJump * Zoom
		ZoomElapsedTime = 0
		Zooming = true
		UpdateCameraZoomConnection = Heartbeat:Connect(UpdateZoom)
	end
end

local function UpdateZoomPinch(Pixels)
	CurrentZoom = math.clamp(CurrentZoom + Height * (Pixels/SizePixelsXY), 0, Height)
	ZoomAlpha = CurrentZoom/Height
end

local LastPositions
local Pinching
local function TouchPinch(Positions, _, _, State, GameProcessedEvent)
	if GameProcessedEvent and not Pinching then return end
	if State == Enum.UserInputState.Change then -- Changed will occur more frequently
		local V2 = Positions[2]
		if V2 then
			UpdateZoomPinch((LastPositions[1] - LastPositions[2]).Magnitude - (Positions[1] - V2).Magnitude)
			LastPositions = Positions
		else
			Pinching = false
		end
	elseif State == Enum.UserInputState.Begin then
		Pinching = true
		LastPositions = Positions
	else
		Pinching = false
	end
end

local MoveElapsedTime
local KeysDown
local function MoveCamera(DeltaTime)
	local Vector = CurrentMovementUnitVector * DeltaTime * (MinSpeed + MaxSpeed * GetSpeed(MoveElapsedTime))
	X = math.clamp(X + Vector.X, 0, MaxX)
	Z = math.clamp(Z + Vector.Z, 0, MaxZ)
	NormalisedX = X/MaxX
	NormalisedZ = Z/MaxZ
	MoveElapsedTime += DeltaTime
end

local function InputBeganHandler(Input, GameProcessedEvent)
	if GameProcessedEvent then return end
	if not (Input.UserInputType == Enum.UserInputType.Keyboard) then return end
	local Movement = MovementVectorTable[Input.KeyCode]
	if Movement then
		KeysDown += 1
		CurrentMovementVector += Movement
		CurrentMovementUnitVector = (CurrentMovementVector == ZeroVector) and CurrentMovementVector or CurrentMovementVector.Unit 
		if not UpdateCameraPositionConnection then
			MoveElapsedTime = 0
			UpdateCameraPositionConnection = Heartbeat:Connect(MoveCamera)
		end
	end
end


local function InputEndedHandler(Input, GameProcessedEvent)
	if GameProcessedEvent then return end
	if not (Input.UserInputType == Enum.UserInputType.Keyboard) then return end
	local Movement = MovementVectorTable[Input.KeyCode]
	if Movement then
		KeysDown -= 1
		CurrentMovementVector -= Movement
		CurrentMovementUnitVector = CurrentMovementVector.Unit 
		if KeysDown == 0 then
			UpdateCameraPositionConnection:Disconnect() 
			UpdateCameraPositionConnection = nil
		end
	end
end

local function AbsoluteSizeChanged()
	local AbsoluteSize = ScreenGui.AbsoluteSize
	SizePixelsXY = (AbsoluteSize.X^2 + AbsoluteSize.Y^2)^(0.5)
end

ScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(AbsoluteSizeChanged)
AbsoluteSizeChanged()

---- Public Functions ----
function module.StartPanning(CameraInstance, MX, MZ, MH, SX, SZ, SH, ForwardVector, BottomLeftCornerPosition) -- start panning, camera instance, max x, max z, max height, starting x, starting z, starting height) forward vector, botttom left corner
	local UpVector 
	Camera = CameraInstance	
	MaxX, MaxZ, Height = MX, MZ, MH
	CurrentZoom = MH - SH
	SubNormalisedVector = Vector3.new(SX/MX, SH/MH, SZ/MZ)
	ForwardVector = ForwardVector --  ForwardVector is assumed to be a unit vector
	RightVector = CFrame90Y * ForwardVector 
	UpVector = CFrame90X * ForwardVector
	X, Z, CurrentZoom = SX, SZ, SH
	ZoomAlpha = SH/MH
	CurrentMovementVector = ZeroVector
	KeysDown = 0
	OrientationCalculationCFrame = CFrame.fromMatrix(ZeroVector, RightVector * MX, UpVector * MH, ForwardVector * MZ)
	PositionCalculationCFrame = OrientationCalculationCFrame + BottomLeftCornerPosition
	CurrentCFrame = PositionCalculationCFrame 
	ScrollPinchConnection = UserInputService.TouchPinch:Connect(TouchPinch)
	ScrollMouseWheelConnection = UserInputService.PointerAction:Connect(UpdateZoomPointerAction)
	InputBeganConnection = UserInputService.InputBegan:Connect(InputBeganHandler)
	InputEndedConnection = UserInputService.InputEnded:Connect(InputEndedHandler)
	UpdateCameraConnection = Heartbeat:Connect(UpdateCameraCFrame)
end

function module.StopPanning() -- stop panning
	UpdateCameraConnection:Disconnect() 
	InputBeganConnection:Disconnect()
	InputEndedConnection:Disconnect()
	ScrollPinchConnection:Disconect()
	ScrollMouseWheelConnection:Disconnect()
	
end

return module
