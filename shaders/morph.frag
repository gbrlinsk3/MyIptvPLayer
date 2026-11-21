// Transição "derretendo" entre duas imagens (modo "melt" do MorphSlider, do React
// Bits): as duas imagens são deslocadas por ruído fractal e a mistura avança
// seguindo o mesmo ruído. O ruído é calculado aqui mesmo, sem textura.
//
// Ficam de fora do original o brilho/desvio de cor extra da deriva (uDrift) e a
// vinheta com cor de sobreposição, que não fazem sentido para um fundo de banner.
#include <flutter/runtime_effect.glsl>

precision highp float;

// Tamanho da área desenhada, em pixels.
uniform vec2 uSize;
// 0 = só a imagem de origem, 1 = só a de destino (já com a curva aplicada).
uniform float uProgress;
// 1 = coordenadas fora da imagem repetem a borda (preenche tudo, como "cover");
// 0 = fora da imagem fica transparente (ex.: "contain" com faixas).
uniform float uEdge;
// Mapa pixel da tela -> coordenada da imagem (0..1): uv = pixel * xy + zw.
// Calculado no Dart a partir de fit/alignment e do tamanho de cada imagem.
uniform vec4 uFromMap;
uniform vec4 uToMap;

uniform sampler2D uFrom;
uniform sampler2D uTo;

out vec4 fragColor;

const float PI = 3.14159265359;
// Valores padrão do MorphSlider.
const float INTENSITY = 0.55;
const float NOISE_SCALE = 2.4;
const float ABERRATION = 0.35;

float hash21(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
    v += a * noise(p);
    p *= 2.0;
    a *= 0.5;
  }
  return v;
}

// Coordenada da tela (0..1) -> coordenada da imagem.
vec2 toImage(vec2 screenUv, vec4 map) {
  return screenUv * uSize * map.xy + map.zw;
}

// 1 se a coordenada cai dentro da imagem (ou sempre 1 quando uEdge = 1).
float coverage(vec2 imgUv) {
  vec2 inside = step(vec2(0.0), imgUv) * step(imgUv, vec2(1.0));
  return max(inside.x * inside.y, uEdge);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float p = clamp(uProgress, 0.0, 1.0);
  float env = sin(p * PI);

  float nn = fbm(uv * NOISE_SCALE);
  float warp = fbm(uv * NOISE_SCALE * 1.7);
  vec2 g = vec2(nn, warp) - 0.5;
  vec2 uvC = uv + g * INTENSITY * 0.5 * p;
  vec2 uvN = uv - g * INTENSITY * 0.5 * (1.0 - p);
  float m = smoothstep(nn - 0.15, nn + 0.15, p);

  vec2 sC = toImage(uvC, uFromMap);
  vec2 sN = toImage(uvN, uToMap);
  float ca = ABERRATION * env * 0.03;

  vec4 cr = texture(uFrom, clamp(sC + vec2(ca, 0.0), 0.0, 1.0));
  vec4 cg = texture(uFrom, clamp(sC, 0.0, 1.0));
  vec4 cb = texture(uFrom, clamp(sC - vec2(ca, 0.0), 0.0, 1.0));
  vec4 nr = texture(uTo, clamp(sN + vec2(ca, 0.0), 0.0, 1.0));
  vec4 ng = texture(uTo, clamp(sN, 0.0, 1.0));
  vec4 nb = texture(uTo, clamp(sN - vec2(ca, 0.0), 0.0, 1.0));

  // Cores já vêm multiplicadas pelo alfa (padrão do Flutter).
  vec4 colC = vec4(cr.r, cg.g, cb.b, cg.a) * coverage(sC);
  vec4 colN = vec4(nr.r, ng.g, nb.b, ng.a) * coverage(sN);

  fragColor = mix(colC, colN, m);
}
