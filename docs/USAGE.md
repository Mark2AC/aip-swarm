# USAGE — 설치 · 빌드 · 실행 · 운용

> 구조는 [`ARCHITECTURE.md`](ARCHITECTURE.md), 보안은 [`SECURITY.md`](SECURITY.md).
> 전제: 전용 Wi-Fi AP `AIP_FLEET`(192.168.0.0/24), `ROS_DOMAIN_ID=42`, `RMW=rmw_fastrtps_cpp`.

**두 가지 진입 경로** — 하드웨어 없이 개발하려면 **① 시뮬**, 실차 운용은 **② 중앙 PC + 차량**.

---

## 1. 클론

```bash
git clone --recursive https://github.com/Mark2AC/aip-swarm.git   # 서브모듈(rf2o) 포함
# 이미 클론했다면: git submodule update --init --recursive
```

---

## 2. 시뮬 (하드웨어 없이 E2E) — Ubuntu/Windows 공통

경량 2D numpy 시뮬(`aip_fleet_sim`)이 실제 `central.launch`를 그대로 include → supervisor/watchdog/
대시보드가 실기와 동일 경로로 검증된다. Gazebo/GPU 불필요.

```bash
# Docker 시뮬 스택
docker compose -f docker/sim/docker-compose.yml up --build
# 웹 대시보드 → http://localhost:8080

# 또는 네이티브(빌드 후)
ros2 launch aip_fleet_sim fleet_sim.launch.py    # world + 차량×3 + lidar + supervisor + watchdog
```

---

## 3. 중앙 PC 설정 (Ubuntu 22.04, 192.168.0.9)

### 3.1 기초 + Docker
```bash
sudo apt update && sudo apt install -y curl git rsync net-tools openssh-server
# Docker + Compose v2 (공식 apt repo) 설치 후:
sudo usermod -aG docker $USER   # 재로그인
```

### 3.2 ROS2 Humble + 워크스페이스 빌드
```bash
sudo apt install -y software-properties-common && sudo add-apt-repository universe
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
    http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | \
    sudo tee /etc/apt/sources.list.d/ros2.list >/dev/null
sudo apt update && sudo apt install -y ros-humble-desktop ros-humble-twist-mux \
    ros-humble-foxglove-bridge python3-colcon-common-extensions python3-rosdep
sudo rosdep init 2>/dev/null; rosdep update

cd ~/aip_swarm_ws && source /opt/ros/humble/setup.bash
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install
```

### 3.3 Docker Central 스택 + 관제 노드
```bash
# .env 생성 (InfluxDB 크레덴셜 — docker/central/.env.example 복사 후 채움)
cp docker/central/.env.example docker/central/.env   # 강한 password + 64hex 토큰 채우기
sudo mkdir -p /opt/aip && sudo cp config/fastdds_client_profile.xml /opt/aip/

cd docker/central && docker compose up -d && docker compose ps   # fastdds-ds/uros-agent/influxdb ...

# 관제 노드(대시보드·supervisor·watchdog·keepout)
source ~/aip_swarm_ws/install/setup.bash
export ROS_DOMAIN_ID=42
ros2 launch aip_fleet_bringup central.launch.py           # 대시보드 → http://localhost:8080
```
> 방화벽(UFW 사용 시): `192.168.0.0/24`에 대해 `11811/udp`(DDS DS)·`8888/udp`(µROS)·`22/tcp` 허용, 외부는 거부.
> 재부팅 자동기동은 `docker/central/aip-central.service`(systemd) 설치.

---

## 4. 차량 RPi4B 설정 (aip1/aip2/aip3 공통 → 차량별 추가)

**공통(§1→§4 순서 준수)**: Ubuntu 22.04 Server arm64(4GB+, USB SSD 권장). ROS2 apt 저장소 등록 →
`ros-humble-ros-base ros-dev-tools` → 클론(--recursive) → `rosdep install`(핵심: nav2/slam/twist_mux 자동).

```bash
# ROS2 apt 등록 후:
sudo apt install -y ros-humble-ros-base ros-dev-tools python3-colcon-common-extensions
cd ~/aip_swarm_ws && source /opt/ros/humble/setup.bash
rosdep install --from-paths src --ignore-src -r -y --skip-keys "gazebo_ros ignition-gazebo ros_gz_sim"
colcon build --symlink-install --packages-skip aip_fleet_gazebo aip_fleet_sim aip_fleet_foxglove_panels
```
> RPi4B 4GB OOM 주의: `--parallel-workers 1 --executor sequential` + 2GB swap. 또는 중앙 PC 빌드본 복사.

**차량별 추가**:
- **aip1**: `sudo apt install ros-humble-ydlidar-ros2-driver` + `pip3 install pyserial` (+ camera_ros)
- **aip2**: `sudo apt install ros-humble-turtlebot3 ros-humble-turtlebot3-bringup`, `export TURTLEBOT3_MODEL=burger`
- **aip3**: (현재 없음 — STS3215/LiDAR 드라이버 추후)

**환경변수 영구화**(`~/.bashrc`):
```bash
source /opt/ros/humble/setup.bash
source ~/aip_swarm_ws/install/setup.bash
export ROS_DOMAIN_ID=42
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
# aip2만: export TURTLEBOT3_MODEL=burger
```
> ⚠️ 미소싱 시 `ROS_DOMAIN_ID=0`으로 떠 플릿과 통신 안 됨. 새 터미널마다 `echo $ROS_DOMAIN_ID`(=42) 확인.

---

## 5. 실차 기동

### aip1 (메인 AGV — RPi에서)
```bash
# 재기동 전 프로세스 정리
pkill -9 -f "ros2 launch|ydlidar_ros2|twist_mux|heartbeat_pub|serial_bridge|static_transform"; sleep 2
# HW 드라이버 (YDLidar + ESP32 serial_bridge + twist_mux + heartbeat)
ros2 launch aip_fleet_real fleet_main.launch.py         # LiDAR만: with_base:=false
```
확인: `ros2 topic hz /aip1/scan`(~10Hz), `/aip1/odom`(~20Hz), `/aip1/heartbeat`, `/aip1/enc_ticks`.

> **nohup 원격 실행**: `.bashrc` guard 때문에 반드시 경로를 직접 source —
> `nohup bash -c "source /opt/ros/humble/setup.bash; source ~/aip_swarm_ws/install/setup.bash; export ROS_DOMAIN_ID=42; ros2 launch aip_fleet_real fleet_main.launch.py" >/tmp/fm.log 2>&1 </dev/null &`

**중앙 PC(aip1 자율주행)**: `ros2 launch aip_fleet_real main_agv.launch.py` (SLAM+Nav2+patrol).
저장맵 운영: `localization:=amcl map_yaml:=<맵>` (저부하). SLAM 매핑: `localization:=slam`(기본).

### aip2 (TurtleBot3)
```bash
ros2 launch aip_fleet_real turtlebot3.launch.py
```
> ⚠️ TB3 기본 bringup은 TF를 prefix 없이 발행 → `frame_prefix:=aip2/` 배선 필요(담당 팀원).

### 수동 구동 테스트
```bash
ros2 topic pub /aip1/autonomy_cmd_vel geometry_msgs/msg/Twist \
  "{linear: {x: 0.1}, angular: {z: 0.0}}" --rate 10 --times 50   # 직진 5초
ros2 topic echo /aip1/enc_ticks
```

---

## 6. 웹 대시보드 사용 (http://localhost:8080)

중앙 PC `central.launch.py` 기동 시 활성. 브라우저 접속 후:
- **수동 주행**: goto/WASD 드라이브(deadman, `override_cmd_vel` priority 80)
- **목표 이동**: 맵 클릭 → navigate (`AIP_NAV_ALLOWED_IDS` 설정 필요)
- **순찰**: 웨이포인트 편집·시작/정지 · **금지구역**: 폴리곤 → Nav2 costmap 차단
- **E-Stop**: 차량별/전체 (수동 즉시 정지)
- **영상/열화상**: aip1 camera_ros 피드 오버레이 + 온도 심부 마커
- **서보암**: aip1 4축 CCTV형 PTZ 제어(계획)

---

## 7. 중앙 제어 AI (Fleet Brain) — 계획

Fleet Brain은 **설계 단계**이며 본 리포에는 코드가 없다(별도 개발 트랙). 청사진은
[`CENTRAL_AI.md`](CENTRAL_AI.md), 로드맵은 [`ROADMAP.md`](ROADMAP.md) §3.

설계상 배포 원칙: 중앙 PC는 학습 프레임워크 불필요(추론만, 오프라인·로컬). 대시보드는 이미
`/fleet/suggestions`(JSON) 제안 카드 → 운영자 승인 → 기존 명령 경로 실행을 수용하도록 계약돼 있다.

---

## 8. 검증 체크리스트

```bash
ros2 topic list | sort                      # /fleet/status, /{vid}/heartbeat 등
ros2 topic echo /fleet/status --once        # 차량 상태 집계
ros2 topic echo /aip1/heartbeat --once --qos-reliability reliable
docker compose -f docker/central/docker-compose.yml ps   # 컨테이너 Up
```

## 9. 트러블슈팅

| 증상 | 점검/해결 |
|---|---|
| `ros2 topic list` 비어 있음 | `echo $ROS_DOMAIN_ID`(=42), RMW=fastrtps, AP 접속, DS(11811) 도달 |
| `ros-humble-*` apt 못 찾음 | ROS2 저장소 키/`ros2.list` 등록, `apt update` 재실행 |
| `rosdep` 의존 못 잡음 | `rosdep update` 재실행, 필요 시 nav2/slam/twist_mux 수동 apt |
| `/aip1/scan|odom` 없음 | `/dev/ydlidar`·`/dev/aip_esp32` 존재, udev, `pip3 install pyserial` |
| `ros2 topic echo` 수신 안 됨 | `--qos-reliability reliable`(발행이 RELIABLE) |
| aip2 `map↔odom` TF 없음 | slam_toolbox 생존 + frame_prefix 배선(§5) |
| 빌드 OOM(RPi) | `--parallel-workers 1 --executor sequential` + swap, Gazebo/sim 패키지 skip |
