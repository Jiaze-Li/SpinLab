# 3w AHE 物理推演

> 本文档跟踪 3w 异常霍尔效应测量的完整物理推导链，
> 服务于 `ThreeOmegaFitUseCase` / `ThreeOmegaScalingUseCase` 的实现正确性审查。

---

## 0. 原始数据与出处

实验产生 6 个原始量，所有派生量均从这 6 个出发：

| 原始量 | 含义 | 文件 | 列 |
|---|---|---|---|
| `V3w_xy(H)` | 第三谐波横向电压 | field sweep | col5 |
| `Vw_xy(H)` | 第一谐波横向电压 | field sweep | col1 |
| `R1w_xy(H)` | 第一谐波横向电阻（仪器预算） | field sweep | col9 |
| `Vxx(T)` | 纵向电压随温度 | RT | col1 |
| `Rxx(T)` | 纵向电阻随温度（仪器预算） | RT | col9 |
| `H` | 外加磁场 | field sweep | col0 |

几何参数（器件固定值，非测量量）：`Lxx`（μm），`Lxy`（μm），`d`（nm）

**派生量：**

```
Ixx     = Vw_xy / R1w_xy            [A]   从 field sweep 反算，per temperature
R3w_xy  = V3w_xy / Ixx              [Ω]   不是原始数据
```

---

## 1. 信号结构与线性背底减除

两个横向电压信号 Vw_xy 和 V3w_xy 均采用相同方案。

### 1.1 信号结构（两个信号通用）

任一横向电压 V(H) 在高场饱和区可写为：

```
H > 0 高场：  V(H) = +V_sat + k·H + C
H < 0 高场：  V(H) = -V_sat + k·H + C
```

| 项 | 含义 |
|---|---|
| ±V_sat | AHE 饱和值，H 变号时反向 |
| k·H | 线性背底（普通霍尔等），关于 H 为奇函数 |
| C | 仪器常数偏置 |

### 1.2 直接读零场的问题

H=0 处 k·0 = 0，看似背底不影响，但：

- H=0 点受磁滞影响，磁化状态未必确定
- 没有利用高场区统计平均，信噪比差

### 1.3 方案A（采用）：高场线性外推取 y 轴截距

对正高场区（H > f·Hmax，f = 0.70）做线性拟合：

```
V(H) = k+·H + b+
```

对负高场区（H < -f·Hmax）做线性拟合：

```
V(H) = k-·H + b-
```

截距含义：

```
b+ = +V_sat + C
b- = -V_sat + C
```

斜率 k 被拟合吸收，C 被相减消去，得到 H=0 处的 AHE 电压：

```
V_AHE = (b+ - b-) / 2 = V_sat
```

**为何选方案A而非垂直距离 V_sat/sqrt(1+k²)：**
V_AHE 的物理定义是 H=0 时霍尔方向的电压，对应 y 轴截距。
垂直距离是几何构造，没有对应的实验测量量。

### 1.4 应用到两个信号

对 Vw_xy(H) 和 V3w_xy(H) 各自独立执行同一流程：

**步骤一：高场线性拟合（正负支各一次）**

```
正支（H > f·Hmax）：V = k+·H + b+
负支（H < -f·Hmax）：V = k-·H + b-
背底斜率：k = (k+ + k-) / 2
```

**步骤二：减去线性背底（用于画图）**

```
V_corrected(H) = V(H) - k·H
```

减背底后信号在高场区变为平坦，磁滞回线呈方形，Hc 和 V_AHE 直观可读。

**步骤三：提取 AHE 值**

```
V_AHE = 正高场区 V_corrected 的平均值
      = (b+ - b-) / 2          ← 数学等价
```

步骤二和步骤三共用同一次拟合，不重复计算。

```
Vw_AHE  = (b+_Vw  - b-_Vw)  / 2
V3w_AHE = (b+_V3w - b-_V3w) / 2
```

全程在原始电压上操作，不经过除以 Ixx 再乘回的循环。

---

## 2. 每个温度提取一个 (X, Y) 数据点

### 2.1 输入

```
field sweep at T：V3w_xy(H), Vw_xy(H), R1w_xy(H)
RT 文件：        Rxx(T)
几何参数：       Lxx, Lxy, d
```

### 2.2 步骤

```
1. Ixx(T)      = mean( Vw_xy(H) / R1w_xy(H) )   over all H points   [A]

2. V3w_AHE(T)  = (b+_V3w - b-_V3w) / 2                              [V]
                 （§1.3 高场线性外推，直接在 V3w_xy(H) 上做）

3. Rxx(T)      = RT 文件 col9 在温度 T 处线性插值                    [Ω]

4. Y(T)        = V3w_AHE · Lxx² · d / ( Ixx³ · Rxx(T)² )

5. X(T)        = Lxx² / ( Rxx(T)² · d² · Lxy² )
```

### 2.3 输出

每个 field sweep 温度产生一个点 `(X(T), Y(T))`。
收集所有温度的点，做线性拟合：

```
Y = α · X + β
```

| 系数 | 物理意义 |
|---|---|
| β | Berry 曲率四极矩 Q_xxz（本征贡献，主要结果） |
| α | 外禀斜散射贡献 |

### 2.4 代码待修复项

| 问题 | 位置 | 修复 |
|---|---|---|
| V3w_AHE 直接读 H≈0，未减线性背底 | `ThreeOmegaFitUseCase._v3omegaAtZeroField` | 改为高场线性外推 `(b+ - b-) / 2` |
| Exx 用了 `iAmp = iRms × √2` | `ThreeOmegaScalingUseCase` | 改为直接用 `iRms` |
| 画图未减线性背底 | `ThreeOmegaFitUseCase` | 对 r1omega / r3omega 减去 k·H |

---

## 3. Scaling Law 展开式

### 3.1 中间量定义

```
Exx      = Ixx · Rxx(T) / Lxx                     [V/m]
E3w_AHE  = V3w_AHE / Lxy                          [V/m]
ρ_xx     = Rxx(T) · d · Lxy / Lxx                 [Ω·m]
σ_xx     = Lxx / (Rxx(T) · d · Lxy)               [S/m]
```

注意：`Exx³` 是 Exx 的三次方，不是第三谐波。

### 3.2 展开过程

```
Exx³ · σ_xx = [Ixx³ · Rxx(T)³ / Lxx³] · [Lxx / (Rxx(T) · d · Lxy)]
            = Ixx³ · Rxx(T)² / (Lxx² · d · Lxy)

Y = E3w_AHE / (Exx³ · σ_xx)
  = [V3w_AHE / Lxy] / [Ixx³ · Rxx(T)² / (Lxx² · d · Lxy)]
  = V3w_AHE · Lxx² · d / (Ixx³ · Rxx(T)²)
```

### 3.3 最终形式（纯原始量）

```
Y(T) = V3w_AHE · Lxx² · d / (Ixx³ · Rxx(T)²)

X(T) = σ²_xx = Lxx² / (Rxx(T)² · d² · Lxy²)

Y = α · X + β
```

| 系数 | 物理意义 |
|---|---|
| β | Berry 曲率四极矩 Q_xxz（本征贡献，主要结果） |
| α | 外禀斜散射贡献 |

注意：
- X 轴不含 Ixx
- Y 轴含 Ixx³
- `Ixx` = iRms（rms 值），`I_amp = Ixx · sqrt(2)`（幅值）
- `V3w_AHE` 来自 §1.3 线性背底减除

### 3.4 单位

**SI 推导：**

```
[X] = (S/m)²
[Y] = m³/W = Ω·m³/V²        （因 W = V²/Ω）
```

**显示单位（代码输出采用）：**

```
X：10⁷ S²/cm²
Y：Ω·μm³·V⁻²
```

换算：
```
1 S/cm = 100 S/m  →  (S/cm)² = 10⁴ (S/m)²
1 μm³  = 10⁻¹⁸ m³  →  Ω·μm³/V² = 10⁻¹⁸ Ω·m³/V²
```

---

## 4. TODO

- [x] Ixx 定义：使用 rms 值，I_amp = Ixx · sqrt(2)
- [ ] 代码 bug：现有 Exx 用了 iAmp（iRms × √2），应改为 iRms
- [ ] 量纲与文献核对
- [ ] 高场阈值 f=0.70 是否需要用户可调
- [ ] V3w_AHE 高场点数不足时的 fallback 策略
