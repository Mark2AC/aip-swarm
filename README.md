# AIP Swarm

ROS2 Humble 기반 다중 AGV 자율 군집 시스템 — SLAM/Nav2 자율주행, 순찰, 열화상 이상 감지,
웹 관제 대시보드. 예산 제약 하의 이질 군집(메인 AGV 1대 + 보조 차량 2대)을 단일 ROS2 그래프로
묶고, 중앙 PC에서 관제·상태 감시한다. 중앙 제어 AI(Fleet Brain)는 설계 단계다.

**문서**: [`docs/VISION.md`](docs/VISION.md)(계획·비전) · [`docs/ROADMAP.md`](docs/ROADMAP.md)(개발 로드맵) ·
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)(현재 구조) · [`docs/USAGE.md`](docs/USAGE.md)(설치·사용법).
중앙 AI 설계 [`docs/CENTRAL_AI.md`](docs/CENTRAL_AI.md) · 보안 [`docs/SECURITY.md`](docs/SECURITY.md).

## Scope

- 전 차량(`aip1`, `aip2`, `aip3`)을 단일 ROS2 그래프로 묶는 통신 계약 — 네임스페이스·QoS·discovery.
- 중앙 PC 서비스 스택 — FastDDS Discovery Server / micro-ROS Agent / rosbag2 / InfluxDB / 웹 대시보드.
- 상위 권한 오버라이드 & 워치독, 순찰·금지구역, 영상/열화상 파이프라인.
- ESP32-S3 펌웨어(메인 AGV 구동계).

## Layout

```
aip_swarm_ws/
├── docker/central/           # 중앙 PC 서비스 컨테이너 정의
├── config/                   # DDS·twist_mux·network 구성
├── docs/                     # VISION·ROADMAP·ARCHITECTURE·USAGE (+ CENTRAL_AI·SECURITY)
├── src/
│   ├── aip_fleet_msgs/       # 공통 msg/srv
│   ├── aip_fleet_bringup/    # 중앙 launch (central.launch.py)
│   ├── aip_fleet_real/       # 실차 bringup/config (aip1/aip2/aip3)
│   ├── aip_fleet_supervisor/ # supervisor + watchdog
│   ├── aip_fleet_dashboard/  # FastAPI 웹 관제 서버
│   ├── aip_fleet_perception/ # 열화상·비전·순찰 모니터
│   ├── aip_fleet_sim/        # 경량 2D 시뮬 (차량 없이 E2E 검증)
│   └── … (nav / gazebo / coordinator / autonomous / telemetry)
└── firmware/
    ├── main_agv/             # aip1 ESP32-S3 펌웨어
    └── scout/                # 보조 차량 펌웨어 스켈레톤
```

## Quick start

```bash
git clone --recursive https://github.com/Mark2AC/aip-swarm.git
```

- **하드웨어 없이 (시뮬 E2E)**: `ros2 launch aip_fleet_sim fleet_sim.launch.py` → 대시보드 `http://localhost:8080`
- **중앙 PC 관제**: `docker compose -f docker/central/docker-compose.yml up -d` + `ros2 launch aip_fleet_bringup central.launch.py`
- **실차 기동(aip1)**: `ros2 launch aip_fleet_real fleet_main.launch.py`

설치·빌드·실행·운용 전체는 [`docs/USAGE.md`](docs/USAGE.md).

## 표준 차량 인터페이스 (계약)

각 차량은 자기 네임스페이스(`aip1` / `aip2` / `aip3`) 아래에서 아래를 **동일하게** 제공한다.
상위 스택(coordinator·autonomous·dashboard)은 이 인터페이스만 바라본다.

| 방향 | 토픽 | 타입 | 설명 |
|---|---|---|---|
| pub | `scan` | `sensor_msgs/LaserScan` | LiDAR |
| pub | `odom` | `nav_msgs/Odometry` | TF `odom → base_link`와 정합 |
| pub | `heartbeat` | `aip_fleet_msgs/FleetHeartbeat` | ≥2 Hz |
| sub | `cmd_vel` | `geometry_msgs/Twist` | twist_mux 출력 → 모터 |
| sub | `override_cmd_vel` | `geometry_msgs/Twist` | 중앙 수동 override (priority 80) |
| sub | `autonomy_cmd_vel` | `geometry_msgs/Twist` | Nav2 (priority 10) |
| sub | `estop` | `std_msgs/Bool` | True = 즉시 정지 |

환경변수: `ROS_DOMAIN_ID=42`, `RMW_IMPLEMENTATION=rmw_fastrtps_cpp`. 동일 서브넷은 FastDDS Simple
Discovery로 통신(이기종/VPN 시에만 Discovery Server `.9:11811`). twist_mux 구성은 `config/twist_mux.yaml`.

## 향후 확장

- **Zenoh**: `RMW_IMPLEMENTATION=rmw_zenoh_cpp` 스왑 — 네임스페이스/토픽 계약 유지.
- **SROS2**: keystore 생성 후 launch에 `SROS2_SECURITY_ROOT_DIRECTORY` 주입 (상세 [`docs/SECURITY.md`](docs/SECURITY.md)).
- **보조 차량 업그레이드**: 같은 네임스페이스로 RPi4 ROS2 네이티브 노드 투입 → 대시보드/supervisor 무변경.
- **Fleet Brain**: 중앙 제어 AI 구현 (설계 [`docs/CENTRAL_AI.md`](docs/CENTRAL_AI.md)).

## License

Apache-2.0 — [`LICENSE`](LICENSE). 기여자 [`CONTRIBUTORS.md`](CONTRIBUTORS.md).
