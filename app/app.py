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
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def broadcast(self, message: str):
        for connection in self.active_connections:
            try:
                await connection.send_text(message)
            except Exception as e:
                print(f"Broadcast error: {e}")


manager = ConnectionManager()


def run_script(script_path: str) -> str:
    """Execute a script from the scripts/ directory and return its output."""
    try:
        output = subprocess.check_output(["bash", script_path], universal_newlines=True)
    except Exception as e:
        output = f"Error running {script_path}: {str(e)}"
    return output


async def monitoring_task():
    """Periodically run monitoring scripts and broadcast their output."""
    while True:
        cpu = run_script("scripts/cpu_status.sh")
        disk = run_script("scripts/disk_status.sh")
        gpu = run_script("scripts/gpu_status.sh")
        fan = run_script("scripts/fan_status.sh")
        dashboard = (
            "==== CPU Status ====\n" + cpu +
            "\n==== Disk Status ====\n" + disk +
            "\n==== GPU Status ====\n" + gpu +
            "\n==== Fan Status ====\n" + fan
        )
        data = {
            "cpu": cpu,
            "disk": disk,
            "gpu": gpu,
            "fan": fan,
            "dashboard": dashboard
        }
        message = json.dumps(data)
        await manager.broadcast(message)
        await asyncio.sleep(2)  # Update interval


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: start the background monitoring task
    task = asyncio.create_task(monitoring_task())
    yield
    # Shutdown: cancel the background task
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass


app = FastAPI(lifespan=lifespan)


@app.get("/", response_class=HTMLResponse)
async def get_index(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            # Keep connection open; no incoming messages expected.
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)
