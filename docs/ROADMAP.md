# ROADMAP — 개발 로드맵

> 세대별 목표와 현재 진행 상황, 남은 작업. 비전은 [`VISION.md`](VISION.md),
> 현재 구조는 [`ARCHITECTURE.md`](ARCHITECTURE.md).

---

## 1. 세대별 로드맵

### 1세대 (현재) — 예산 제약 이질 군집
```
중앙 PC (항상 켜져 있음)
  ├── supervisor: 군집 상태 모니터        ├── watchdog: 장애 감지 → 전체 E-Stop
  ├── coordinator: 편대 추종 계산          ├── dashboard: 웹 관제 (FastAPI+WS)
  └── (Fleet Brain: 커버리지/이상 대응 제안 — 설계 단계)

메인 AGV(aip1, 완전 사양)        보조 차량 × 2 (aip2/aip3)
  ├── LiDAR + SLAM → 절대 측위     ├── RPi4B + (ESP32/OpenCR)
  └── Nav2 자율주행 + 열화상       └── 위치: 메인 카메라/향후 UWB 의존
```
**한계**: 보조 차량 독립 측위 미확보, 중앙 PC 다운 시 제어 불능.

### 2세대 (중기) — 자기 위치 확보
각 차량에 **UWB + 휠 엔코더 + IMU** 추가 → 자차가 스스로 위치 파악(엔코더/IMU 누적 →
UWB ranging 보정 → 메인 LiDAR SLAM 절대 기준). 중앙 PC 역할 축소(대시보드 + 임무 할당).

### 3세대 (장기) — 완전 분산 군집
각 차량 동등 사양(SLAM/UWB 절대측위 + 로컬 플래너 + 이웃 상태 구독 → 협력 계획 + 임무 인계 +
탈락 시 재편성). 통신 완전 P2P(FastDDS unicast, 중앙 DS 선택), 보안 SROS2. **중앙 PC 없어도 운용 가능.**

---

## 2. 현재 진행 상황

| 영역 | 상태 | 비고 |
|---|---|---|
| aip1 실차 (SLAM+Nav2+순찰) | ✅ 운용 | 실차 완전 가동 검증, 매핑 안정화(deskew) |
| aip1 영상/열화상 | ✅ | camera_ros HW-ISP 피드 + 대시보드 오버레이, 열상 INFERNO viz |
| aip2 (TurtleBot3) | 🔧 세팅 중 | TF frame_prefix 결정 필요(담당 팀원) |
| aip3 (자작 차량) | 🔧 세팅 중 | STS3215 구동계 동작(컨테이너), 저장소 launch는 placeholder |
| 웹 관제 대시보드 | ✅ | 수동 제어·순찰·금지구역·서보암 PTZ·영상 오버레이 |
| 차량 Wi-Fi 워치독 | ✅ | GW 도달성 실패 시 wlan0 단계적 재연결 |
| 실차 부하/SSH 안정화 | ✅ 코드 / ⏳ 실차 검증 | launch staggering + AMCL 저장맵 모드 |
| 시뮬 E2E (2D + Gazebo) | ✅ | 하드웨어 없이 전 파이프라인 검증 |
| **Fleet Brain (중앙 AI)** | 🔬 설계 확정(청사진) | 아래 §3 — 구현은 별도 트랙, 본 리포 미포함 |
| CI (colcon build+test) | ✅ | GitHub Actions |

---

## 3. Fleet Brain (중앙 제어 AI) 로드맵

**상태: 설계 골격 확정, 코드 미구현.** 청사진은 [`CENTRAL_AI.md`](CENTRAL_AI.md).
AI 학습·정책 엔진 구현은 **별도 개발 트랙**에서 진행하며, 본(main) 리포에는 포함하지 않는다.

- **확정된 원칙**: 로컬 규칙/경량 ML(클라우드 LLM 배제), **제안만(human-in-the-loop)**,
  플릿망만(외부 인터넷 차단), 결정론·오프라인·저지연.
- **책임 범위(계획)**: ① 이상징후 트리아지 + 출동 ② 순찰 스케줄링/최적화 ③ 차량 상태·장애 대응
  ④ 커버리지 배치(기하 분할 / 학습 정책).
- **통합 방식(계획)**: `/fleet/suggestions`(JSON) 발행 → 대시보드 제안 카드 → 운영자 승인 →
  기존 명령 경로(`cmd_navigate`/patrol → Nav2)로만 실행. 안전 정지(watchdog)는 AI와 분리.
- **선행 조건**: 실차 매핑 데이터, 실 Nav2 구동 환경, 이상 라벨 데이터 수집.

## 4. 측위 하드웨어 업그레이드 경로 (보조 차량)

| 단계 | 내용 | 예산(대략) |
|---|---|---|
| 0단계(현재) | 통신만 — heartbeat/cmd_vel, 위치는 메인 카메라(ArUco) 의존 | — |
| 1단계 | 자기 위치 인식 — UWB + 엔코더 + IMU → `/<ns>/odom` 독립 발행 | ~9만 원/대 |
| 2단계 | 환경 인식 + 자율 회피 (근접 센서) | +5만 원 |
| 3단계 | 독립 SLAM (완전 사양 동급) | +22만 원 |

---

## 5. 남은 구조적 약점 · 의사결정

- **보조 차량 절대 측위**: 현재 ArUco 카메라 앵커(`scout_localizer_node`) 채택·구현, 하드웨어 연동은 카메라 구매·캘리브레이션 후. UWB로 단계 전환 예정.
- **aip2 TF frame_prefix**: TB3 기본 bringup이 prefix 없이 TF 발행 → SLAM/Nav2 정합 배선 필요(담당 팀원 실차 결정).
- **aip3 드라이버**: Feetech STS3215 + LiDAR ROS2 드라이버 저장소 통합 미완.
- **텔레메트리**: InfluxDB 브리지(`aip_fleet_telemetry`) 완료, Grafana 대시보드 JSON은 실 데이터 수집 후.
- **보안**: MVP는 평문 DDS. 실증 전 SROS2 키스토어 + Foxglove 인증. 상세 [`SECURITY.md`](SECURITY.md).
- **다중 SLAM 맵 공유**: m-explore map_merge vs 중앙 맵 서버 — 실차 전환 시 결정.
- **Fleet Brain**: 설계만 확정(§3), 구현·통합은 선행 조건 충족 후 별도 트랙.

## 6. 실차 전환 준비 (별도 세션)

`use_sim_time` 일괄 false 전환 · 차량별 LiDAR 설정 · STS3215 ros2_control · 차량별 bringup launch · UWB 노드 제거(1세대). 상세는 [`USAGE.md`](USAGE.md) 실차 섹션.
