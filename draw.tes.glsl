/*
 * Copyright (c) 2016-2022, NVIDIA CORPORATION.  All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-FileCopyrightText: Copyright (c) 2016-2022 NVIDIA CORPORATION
 * SPDX-License-Identifier: Apache-2.0
 */


#version 450

#ifdef VULKAN
  #extension GL_GOOGLE_include_directive : enable
  #extension GL_EXT_control_flow_attributes: require
  #define UNROLL_LOOP [[unroll]]
#else
  #extension GL_ARB_shading_language_include : enable
  #pragma optionNV(unroll all)
  #define UNROLL_LOOP
#endif

#include "common.h"

//////////////////////////////////////////////////
// UNIFORMS

#if IS_VULKAN

  layout(std140,binding= SCENE_UBO_VIEW,set=DSET_SCENE) uniform sceneBuffer {
    SceneData scene;
  };

#else

#endif

//////////////////////////////////////////////////
// INPUT

layout(quads, equal_spacing, cw) in;

//////////////////////////////////////////////////
// OUTPUT

#if SHOW_PRIMIDS

  // nothing to output

#else

  layout(location=0) out Interpolants {
    vec3  wPos;
    vec3  wNormal;
    flat uint meshletID;
  #if VERTEX_EXTRAS_COUNT
    vec4 xtra[VERTEX_EXTRAS_COUNT];
  #endif
} OUT;

#endif

//////////////////////////////////////////////////
// TESSELLATION EVALUATION SHADER EXECUTION

#define BICUBIC_BSPLINE 1
#if !BICUBIC_BSPLINE
#define SECOND_CONTINOUS 0
#endif
#define CHECK_SINGLE_LOOP 0
#if CHECK_SINGLE_LOOP
#define LOOP_COUNT 0
#else
#define LOOP_COUNT 5
#endif

#if BICUBIC_BSPLINE
const float BSPLINE_HEIGHT_SCALE = 1.5f;
#endif
const float PI = 3.14159265359;

#if BICUBIC_BSPLINE
struct control_bicubic_height
{
  vec4 val[4];
};

vec4 bspline_coefficient(float u)
{
  float u2 = u * u;
  float u3 = u * u2;
  float s = 1.0f / 6.0f;

  vec4 b = vec4(0.0f);
  b[0] = (1.0f - 3.0f*u + 3.0f*u2 - u3) * s;
  b[1] = (4.0f - 6.0f*u2 + 3.0f*u3) * s;
  b[2] = (1.0f + 3.0f*u + 3.0f*u2 - 3.0f*u3) * s;
  b[3] = u3 * s;

  return b;
}

vec4 bspline_derivative_coefficient(float u)
{
   float u2 = u * u;
   float s = 0.5f;

   vec4 b = vec4(0.0f);
   b[0] = (-1.0f + 2.0f*u - u2) * s;
   b[1] = (-4.0f*u + 3.0f*u2) * s;
   b[2] = (1.0f + 2.0f*u - 3.0f*u2) * s;
   b[3] = u2 * s;

   return b;
}

float bspline_s(vec4 val, float u)
{
  vec4 coeff = bspline_coefficient(u);
  return dot(coeff, val);
}

float bspline_ds(vec4 val, float u)
{
  vec4 coeff = bspline_derivative_coefficient(u);
  return dot(coeff, val);
}

vec3 bspline_z(control_bicubic_height bicubic_height, float x, float y)
{
  vec4 zx = vec4(0.0f);
  zx[0] = bspline_s(bicubic_height.val[0], x);
  zx[1] = bspline_s(bicubic_height.val[1], x);
  zx[2] = bspline_s(bicubic_height.val[2], x);
  zx[3] = bspline_s(bicubic_height.val[3], x);
  float z = bspline_s(zx, y);

  vec4 dzx = vec4(0.0f);
  dzx[0] = bspline_ds(bicubic_height.val[0], x);
  dzx[1] = bspline_ds(bicubic_height.val[1], x);
  dzx[2] = bspline_ds(bicubic_height.val[2], x);
  dzx[3] = bspline_ds(bicubic_height.val[3], x);
  float dzdx = bspline_s(dzx, y);

  float dzdy = bspline_ds(zx, y);

  return vec3(dzdx, dzdy, z);
}

control_bicubic_height rand_bicubic_height(ivec2 uv)
{
  int u[4] = {uv.x - 1, uv.x, uv.x + 1, uv.x + 2};
  int v[4] = {uv.y - 1, uv.y, uv.y + 1, uv.y + 2};

  vec4 s = vec4(0.0f);
  vec4 t = vec4(0.0f);
  for (int k = 0; k < 4; ++k)
  {
    s[k] = 50.0f * fract(u[k] / PI);
    t[k] = 50.0f * fract(v[k] / PI);
  }

  control_bicubic_height bicubic_height;
  for (int i = 0; i < 4; ++i)
  {
    for (int j = 0; j < 4; ++j)
    {
      bicubic_height.val[i][j] = BSPLINE_HEIGHT_SCALE * (2.0f * fract(s[j] * t[i] * (s[j] + t[i])) - 1.0f);
    }
  }

  return bicubic_height;
}
#else
struct control_height
{
  vec4 val;
};

float fun_s(float u)
{
  float u2 = u * u;
  float u3 = u * u2;
  return 3.0f*u2 - 2.0f*u3;
}

float fun_ds(float u)
{
  float u2 = u * u;
  return 6.0f*u - 6.0f*u2;
}

vec3 fun_z (control_height height, float x, float y)
{
  float a = height.val[0];
  float b = height.val[1];
  float c = height.val[2];
  float d = height.val[3];

  float s_x = fun_s(x);
  float s_y = fun_s(y);

  float z = a +
            (b - a) * s_x +
            (c - a) * s_y +
            (a - b - c + d) * s_x * s_y;

  float dsdx = fun_ds(x);
  float dsdy = fun_ds(y);
  float dzdx = (b - a) * dsdx +
               (a - b - c + d) * s_y * dsdx;
  float dzdy = (c - a) * dsdy +
               (a - b - c + d) * s_x * dsdy;

  return vec3(dzdx, dzdy, z);
}

control_height rand_height(ivec2 uv)
{
  int u0 = uv.x;
  int u1 = uv.x + 1;
  int v0 = uv.y;
  int v1 = uv.y + 1;

#if SECOND_CONTINOUS
  u0 = u0 % 2;
  u1 = u1 % 2;
  v0 = v0 % 2;
  v1 = v1 % 2;
#endif

  float s0 = 50.0f * fract(u0 / PI);
  float s1 = 50.0f * fract(u1 / PI);
  float t0 = 50.0f * fract(v0 / PI);
  float t1 = 50.0f * fract(v1 / PI);

  control_height height;
  height.val[0] = 2.0f * fract(s0 * t0 * (s0 + t0)) - 1.0f;
  height.val[1] = 2.0f * fract(s1 * t0 * (s1 + t0)) - 1.0f;
  height.val[2] = 2.0f * fract(s0 * t1 * (s0 + t1)) - 1.0f;
  height.val[3] = 2.0f * fract(s1 * t1 * (s1 + t1)) - 1.0f;

  return height;
}
#endif

void main()
{
  float z = 0.0f;
  float dzdx = 0.0f;
  float dzdy = 0.0f;

  float scale = 1.0f;
  mat2 rotate = mat2(1.0f, 0.0f,
                     0.0f, 1.0f);

#if CHECK_SINGLE_LOOP
  for (int k = 0; k < LOOP_COUNT; k++)
  {
    scale *= 2;
    rotate *= mat2(0.8f, -0.6f,
                   0.6f,  0.8f);
  }
#endif

  vec2 uv_orig = gl_in[0].gl_Position.xy + gl_TessCoord.xy;
#if CHECK_SINGLE_LOOP
  for (int k = 0; k < 1; k++)
#else
  for (int k = 0; k < LOOP_COUNT; k++)
#endif
  {
    vec2 uv = uv_orig;
    uv = rotate * uv;
    uv *= scale;

    vec2 uv_frac = fract(uv);
    ivec2 uv_int = ivec2(uv - uv_frac); // Note that using ivec2(uv) may need extra handling for negative values.

#if BICUBIC_BSPLINE
    control_bicubic_height bicubic_height = rand_bicubic_height(uv_int);
    vec3 h = bspline_z(bicubic_height, uv_frac.x, uv_frac.y);
#else
    control_height height = rand_height(uv_int);
    vec3 h = fun_z(height, uv_frac.x, uv_frac.y);
#endif

    z += h.z / scale;
    vec2 dz = transpose(rotate) * h.xy;
    dzdx += dz.x;
    dzdy += dz.y;

    rotate *= mat2(0.8f, -0.6f,
                   0.6f,  0.8f);
    scale *= 2.0f;
  }

  vec3 oPos = vec3(uv_orig, z);

  vec3 tangent = vec3(1.0f, 0.0f, dzdx);
  vec3 bitangent = vec3(0.0f, 1.0f, dzdy);
  vec3 oNormal = normalize(cross(tangent, bitangent));

  // Identity world matrix
  vec3 wPos = oPos;
  vec3 wNormal = oNormal;

#if !SHOW_PRIMIDS
  gl_Position = (scene.viewProjMatrix * vec4(wPos,1));
  OUT.wPos = wPos;
  OUT.wNormal = wNormal;
  OUT.meshletID = 0;
#endif
}
