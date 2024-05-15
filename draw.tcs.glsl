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

//////////////////////////////////////////////////
// INPUT

//////////////////////////////////////////////////
// OUTPUT

layout (vertices = 1) out;

//////////////////////////////////////////////////
// VERTEX EXECUTION

void main()
{
  gl_out[gl_InvocationID].gl_Position = gl_in[gl_InvocationID].gl_Position;

  // Set tessellation levels
  gl_TessLevelOuter[0] = 64.0; // Outer tessellation level
  gl_TessLevelOuter[1] = 64.0;
  gl_TessLevelOuter[2] = 64.0;
  gl_TessLevelOuter[3] = 64.0;

  gl_TessLevelInner[0] = 64.0; // Inner tessellation level
  gl_TessLevelInner[1] = 64.0;
}
