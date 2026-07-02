# ARCHITECTURE — AIP Swarm 시스템 구조

> **현재 구현된 코드와 실차 검증 결과 기준.** 왜/무엇은 [`VISION.md`](VISION.md),
> 계획은 [`ROADMAP.md`](ROADMAP.md), 설치·운용은 [`USAGE.md`](USAGE.md).

---

## 0. 전체 구성 한눈에

```
                Wi-Fi AP: AIP_FLEET (192.168.0.0/24) / ROS_DOMAIN_ID=42 / FastDDS Simple Discovery

  중앙 PC (Ubuntu, 192.168.0.9) — aip_swarm_ws 모노레포
  ┌───────────────────────────────────────────────────────────────┐
  │  Docker Central 스택            ros2 launch (네이티브)          │
  │   ├─ dashboard_server (FastAPI+WS:8080)   ├─ main_agv.launch (SLAM+Nav2+patrol, aip1) │
  │   ├─ supervisor_node / watchdog_node       ├─ turtlebot3.launch (aip2)                 │
  │   ├─ keepout_zone_node                      └─ (perception: 영상/열화상 파이프라인)     │
  │   └─ fastdds-ds / uros-agent / influxdb                                                 │
  └───────────────────────────────────────────────────────────────┘
                    │  DDS UDP (Simple Discovery, 동일 서브넷 자동 탐색)
   ─────────────────┼───────────────────────────────────────────────
  RPi4B aip1 (.3)        RPi4B aip2 (.4)          RPi4B aip3 (.5)
  fleet_main.launch      turtlebot3.launch        custom_vehicle.launch
  ├─ ydlidar_driver      ├─ turtlebot3_bringup    (placeholder — STS3215
  ├─ serial_bridge(ESP32)├─ slam_toolbox           드라이버 미구현)
  ├─ camera_ros(HW-ISP)  ├─ nav2_bringup
  ├─ static_tf ×2        ├─ twist_mux
  ├─ twist_mux           └─ heartbeat_pub
  └─ heartbeat_pub
```

## 1. 패키지 구조

```
aip_swarm_ws/src/
├── aip_fleet_msgs          — ROS2 인터페이스 (FleetHeartbeat/Status, PeerPose, OverrideCommand, PerceptionAlert)
├── aip_fleet_supervisor    — 중앙 supervisor + watchdog
├── aip_fleet_coordinator   — 편대 제어 coordinator + (scout/uwb) localizer
├── aip_fleet_autonomous    — patrol_node + keepout_zone_node
├── aip_fleet_dashboard     — FastAPI 웹 관제 서버 (static/index.html, 영상 오버레이)
├── aip_fleet_perception    — 열화상·비전·순찰 모니터 (camera_ros HW-ISP, 열상 INFERNO viz)
├── aip_fleet_bringup       — 중앙 launch (central.launch.py)
├── aip_fleet_real          — 실차 bringup/config (aip1/aip2/aip3)
├── aip_fleet_nav / _gazebo / _sim  — Nav2·SLAM 설정 / Gazebo 시뮬 / 2D numpy 시뮬
├── aip_fleet_telemetry     — InfluxDB 브리지
├── aip_main_description     — aip1 URDF/description
├── aip_fleet_foxglove_panels — (선택) Foxglove TS 패널
└── m-explore-ros2, rf2o_laser_odometry(submodule) — 프론티어 탐사·레이저 오도메트리
firmware/main_agv/          — aip1 ESP32-S3 펌웨어
```
> **중앙 제어 AI(Fleet Brain)** 는 설계 단계이며 본 리포에 코드가 없다(별도 트랙). §7·[`CENTRAL_AI.md`](CENTRAL_AI.md).

## 2. 하드웨어 구성 (요약)

- **주행**: aip1=자작(YDLidar TG15 + ESP32-S3 모터), aip2=TurtleBot3 Burger(OpenCR+LDS-03), aip3=자작(STS3215)
- **온보드**: 각 차량 RPi4B(4GB+, Ubuntu 22.04 arm64)
- **aip1 페이로드**: camera_ros(HW-ISP) 영상 + 열화상 퓨전 센서, 4축 MG996R 서보암(계획)
- **USB 매핑(aip1)**: `/dev/ydlidar`(512000baud), `/dev/aip_esp32`(115200baud) — udev 고정

## 3. 네임스페이스 규약

| 차량 | ns | 플랫폼 | IP | 상태 |
|---|---|---|---|---|
| 메인 AGV | `aip1` | RPi4B+ESP32 | .3 | ✅ 운용 |
| TB3 Burger | `aip2` | RPi4B | .4 | 🔧 세팅 |
| 자작 차량 | `aip3` | RPi4B | .5 | 🔧 세팅 |
| 중앙 PC | — | Ubuntu | .9 | ✅ |

플릿 전역은 `/fleet/*`. (구형 `main`/`scout_N`은 폐기 — 전부 `aipN`.)

## 4. 토픽 그래프 (핵심)

**차량 공통 표준 인터페이스** (§8 계약):
```
출력  /{vid}/scan        LaserScan            출력  /{vid}/odom      Odometry
출력  /{vid}/heartbeat   FleetHeartbeat(2Hz)  입력  /{vid}/cmd_vel   Twist (twist_mux 출력)
입력  /{vid}/override_cmd_vel Twist(원격)     입력  /{vid}/autonomy_cmd_vel Twist(Nav2)
입력  /{vid}/estop       Bool                 TF    map→{odom}→{base}→{laser}
```
**중앙 PC 발행(aip1)**: `/map`(slam_toolbox, TRANSIENT_LOCAL), `/aip1/plan`·`/global|local_costmap/costmap`(Nav2), `/aip1/patrol_status`(JSON).

**플릿 전역 `/fleet/*`**:
| 토픽 | 타입 | 발행→구독 |
|---|---|---|
| `/fleet/status` | FleetStatus | supervisor → watchdog·dashboard (TRANSIENT_LOCAL) |
| `/fleet/override` | OverrideCommand | dashboard·watchdog → supervisor |
| `/fleet/alerts` | PerceptionAlert | patrol_monitor → dashboard |
| `/fleet/peer_poses` | PeerPoseArray | (pose relay) → dashboard·coordinator (TRANSIENT_LOCAL) |
| `/fleet/keepout_zones` / `/fleet/keepout_cloud` | String / PointCloud2 | dashboard → keepout_zone_node → Nav2 costmap |
| `/fleet/suggestions` | String(JSON) | *(계획: Fleet Brain → dashboard 제안 카드)* |

## 5. cmd_vel 우선순위 체인 (모든 차량 공통, twist_mux)

```
estop_lock (lock, 90) 🔒 > override_cmd_vel (80, 원격/대시보드) > coord_cmd_vel (50, 편대)
  > stuck_escape_cmd_vel (15) > autonomy_cmd_vel (10, Nav2)  →  /{vid}/cmd_vel → 모터
```
> HW-EStop(100) > estop_lock(90) > central(80) > fleet_coord(50) > autonomy(10).
> `estop_lock`은 발행자(supervisor) 없으면 항상 locked — 연동 전까지 twist_mux locks 주석.

## 6. 데이터 파이프라인

- **자율주행(aip1)**: LiDAR/ESP32(RPi) →DDS→ 중앙PC slam_toolbox(`/map`)+Nav2(`autonomy_cmd_vel`) →DDS→ RPi twist_mux → ESP32 모터.
- **영상/열화상(aip1)**: camera_ros(HW-ISP) + 열화상 퓨전 →DDS→ 대시보드 오버레이(온도 심부 마커·INFERNO viz).
- **웹 대시보드**: 브라우저 ↔ WebSocket ↔ dashboard_server(rclpy). 구독 `/map`·odom·heartbeat·`/fleet/*`·TF·영상; 발행 `override_cmd_vel`·`estop`·`goal_pose`·`keepout_zones`·순찰·서보암.
- **E-Stop**: dashboard/watchdog → `/fleet/override` → supervisor → `/{vid}/estop`(Bool) → twist_mux estop_lock → 전 모션 차단.
- **차량 Wi-Fi 워치독**: GW 도달성 실패 시 wlan0 단계적 재연결(실차 접속 안정화).

## 7. 중앙 제어 AI (Fleet Brain) — 계획

**설계만 확정, 본 리포에 코드 없음.** 청사진 [`CENTRAL_AI.md`](CENTRAL_AI.md), 로드맵 [`ROADMAP.md`](ROADMAP.md) §3.

설계 요지: **제안만**(차량 직접 제어 금지) → `/fleet/suggestions`(JSON) 발행 → 대시보드 제안 카드 →
운영자 승인 → 기존 명령 경로(`cmd_navigate`/patrol → Nav2)로만 실행. 책임 범위는 이상 트리아지·순찰
스케줄링·차량 상태 대응·커버리지 배치. ESTOP은 watchdog 단독(AI 비간섭).

## 8. QoS · TF · DDS

**QoS**: 센서(odom/scan)·제어(cmd_vel/estop)·heartbeat = RELIABLE/VOLATILE. 상태·맵(`/fleet/status`,
`/map`, peer_poses) = RELIABLE/**TRANSIENT_LOCAL**(latched). `/tf`=VOLATILE, `/tf_static`=TRANSIENT_LOCAL.

**TF(aip1)**: `map → odom(slam) → base_footprint(serial_bridge) → base_link(static) → laser_link(static)`.
aip1은 RSP `frame_prefix=''`라 프레임에 ns 없음(dashboard TF 조회가 분기 처리).

**DDS**: 동일 서브넷은 **FastDDS Simple Discovery**만으로 통신(검증됨). Discovery Server(`.9:11811`)는
이기종 네트워크/VPN 시에만. `ROS_DOMAIN_ID=42`, `RMW=rmw_fastrtps_cpp`.

## 9. launch 진입점

| 위치 | 명령 | 역할 |
|---|---|---|
| RPi(aip1) | `ros2 launch aip_fleet_real fleet_main.launch.py` | HW 드라이버 |
| RPi(aip2) | `ros2 launch aip_fleet_real turtlebot3.launch.py` | TB3 bringup+SLAM+Nav2 |
| 중앙(aip1) | `ros2 launch aip_fleet_real main_agv.launch.py` | SLAM+Nav2+patrol |
| 중앙 관제 | `docker compose -f docker/central/docker-compose.yml up -d` + `central.launch.py` | 대시보드·supervisor·watchdog |
| 시뮬 | `ros2 launch aip_fleet_sim fleet_sim.launch.py` | 2D 시뮬 E2E |

## 10. 표준 차량 인터페이스 (계약)

모든 차량은 아래를 **동일하게** 노출; 상위 스택(coordinator·autonomous·dashboard)은 이 인터페이스만 바라본다.
`{vid}` ∈ {`aip1`,`aip2`,`aip3`}. 출력 `scan`/`odom`/`heartbeat`, 입력 `cmd_vel`/`override_cmd_vel`/`autonomy_cmd_vel`/`estop`, TF `map→{odom}→{base}→{laser}`.

## 11. 알려진 이슈

| 이슈 | 원인 | 해결 |
|---|---|---|
| `/tf_static` RPi→중앙PC 미수신 | FastDDS TRANSIENT_LOCAL 다중호스트 | 중앙 PC가 static TF 재발행(main_agv.launch) |
| `ros2 topic echo /aip1/odom` 안 됨 | RELIABLE 발행 vs BEST_EFFORT 구독 | `--qos-reliability reliable` |
| nohup 시 `ros2: command not found` | `.bashrc` 비대화형 guard | explicit source 경로 사용(USAGE 실차 섹션) |
| aip2 SLAM `map↔base` 실패 | TB3 prefix 없이 TF 발행 | frame_prefix 배선(담당 팀원) |
| estop_lock 항상 locked | twist_mux lock 구독자 없음 | supervisor 연동 전까지 주석 |
