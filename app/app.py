import asyncio
import json
import subprocess
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

templates = Jinja2Templates(directory="templates")

class ConnectionManager:
    def __init__(self):
        self.active_connections = []
        self.subscriptions = {}  # maps websocket -> subscription tab

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
        # Default subscription: full data (dashboard)
        self.subscriptions[websocket] = "dashboard"

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
        if websocket in self.subscriptions:
            del self.subscriptions[websocket]

    async def broadcast(self, full_data: dict):
        for connection in self.active_connections:
            # Determine subscription for this connection.
            tab = self.subscriptions.get(connection, "dashboard")
            if tab == "dashboard":
                data_to_send = full_data
            elif tab in full_data:
                data_to_send = {tab: full_data[tab]}
            else:
                data_to_send = {}
            try:
                await connection.send_text(json.dumps(data_to_send))
            except Exception as e:
                print(f"Broadcast error: {e}")

manager = ConnectionManager()

def run_script_json(script_path: str) -> dict:
    """
    Executes a monitoring script with the "-o json" flag and returns its parsed JSON output.
    """
    try:
        output = subprocess.check_output(
            ["bash", script_path, "-o", "json"],
            universal_newlines=True
        )
        return json.loads(output)
    except Exception as e:
        return {"error": str(e)}

@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(monitoring_task())
    yield
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass

app = FastAPI(lifespan=lifespan)

async def monitoring_task():
    """
    Periodically runs the monitoring scripts, collects their JSON outputs,
    and broadcasts filtered data based on each connection's subscription.
    """
    while True:
        cpu_data = run_script_json("scripts/cpu_status.sh")
        disk_data = run_script_json("scripts/disk_status.sh")
        gpu_data = run_script_json("scripts/gpu_status.sh")
        fan_data = run_script_json("scripts/fan_status.sh")
        
        full_data = {
            "cpu": cpu_data,   # expected to have keys "cpu" and "ram"
            "disk": disk_data, # expected to have key "disks"
            "gpu": gpu_data,   # expected to have key "gpus"
            "fan": fan_data    # expected to have key "fans"
        }
        await manager.broadcast(full_data)
        await asyncio.sleep(2)

@app.get("/", response_class=HTMLResponse)
async def get_index(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            message = await websocket.receive_text()
            try:
                msg = json.loads(message)
                if "tab" in msg:
                    # Update this connection's subscription based on the selected tab.
                    manager.subscriptions[websocket] = msg["tab"]
            except Exception as e:
                print("Error processing message", e)
    except WebSocketDisconnect:
        manager.disconnect(websocket)
