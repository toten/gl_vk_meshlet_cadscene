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
// VERTEX EXECUTION

float fun_s(float x)
{
  return 3*x*x - 2*x*x*x;
}

float fun_ds(float x)
{
  return 6*x - 6*x*x;
}

vec3 fun_z (float a, float b, float c, float d, float x, float y)
{
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

vec4 rand_heights(ivec2 uv)
{
  const float PI = 3.14159265359;

  int u0 = uv.x;
  int u1 = uv.x + 1;
  int v0 = uv.y;
  int v1 = uv.y + 1;

  float s0 = 50.0f * fract(u0 / PI);
  float s1 = 50.0f * fract(u1 / PI);
  float t0 = 50.0f * fract(v0 / PI);
  float t1 = 50.0f * fract(v1 / PI);

  vec4 heights = vec4(0.0f);
  heights.x = 2.0f * fract(s0 * t0 * (s0 + t0)) - 1.0f;
  heights.y = 2.0f * fract(s1 * t0 * (s1 + t0)) - 1.0f;
  heights.z = 2.0f * fract(s0 * t1 * (s0 + t1)) - 1.0f;
  heights.w = 2.0f * fract(s1 * t1 * (s1 + t1)) - 1.0f;

  return heights;
}

void main()
{
  const int LOOP = 5;

  float z = 0.0f;
  float dzdx = 0.0f;
  float dzdy = 0.0f;

  float scale = 1.0f;
  mat2 rotate = mat2(1.0f, 0.0f,
                     0.0f, 1.0f);

#if CHECK_ONE_LOOP
  for (int k = 0; k < LOOP; k++)
  {
    scale *= 2;
    rotate *= mat2(0.8f, -0.6f,
                   0.6f,  0.8f);
  }
#endif

  vec2 uv_orig = gl_in[0].gl_Position.xy + gl_TessCoord.xy;
#if CHECK_ONE_LOOP
  for (int k = 0; k < 1; k++)
#else
  for (int k = 0; k < LOOP; k++)
#endif
  {
    vec2 uv = uv_orig;
    uv = rotate * uv;
    uv *= scale;

    vec2 uv_frac = fract(uv);
    ivec2 uv_int = ivec2(uv - uv_frac);

    vec4 heights = rand_heights(uv_int);
    vec3 h = fun_z(heights.x, heights.y, heights.z, heights.w, uv_frac.x, uv_frac.y);

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
