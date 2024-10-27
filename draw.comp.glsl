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

#version 460

  #extension GL_GOOGLE_include_directive : enable
  #extension GL_EXT_control_flow_attributes: require

#include "config.h"

//////////////////////////////////////

  #extension GL_EXT_shader_explicit_arithmetic_types_int8 : require

/////////////////////////////////////////////////////////////////////////

#include "common.h"

/////////////////////////////////////////////////////////////////////////
// TASK CONFIG

// see Sample::getShaderPrepend() how these are computed
const uint WORKGROUP_SIZE = NVMESHLET_PER_TASK;

layout(local_size_x=WORKGROUP_SIZE) in;

// The workgroup size of the shader may not have enough threads
// to do all the work in a unique thread.
// Therefore we might need to loop to process all the work.

/////////////////////////////////////
// UNIFORMS

  layout(push_constant) uniform pushConstant{
    // x: mesh, y: prim, z: indexOffset, w: indirectCommand
    uvec4     geometryOffsets;
    // x: meshFirst, y: meshMax
    uvec4     drawRange;
  };

  layout(std140, binding = SCENE_UBO_VIEW, set = DSET_SCENE) uniform sceneBuffer {
    SceneData scene;
  };
  layout(std140, binding= 0, set = DSET_OBJECT) uniform objectBuffer {
    ObjectData object;
  };
  
  layout(std430, binding = GEOMETRY_SSBO_MESHLETDESC, set = DSET_GEOMETRY) buffer meshletDescBuffer {
    uvec4 meshletDescs[];
  };
  layout(std430, binding = 1, set = DSET_GEOMETRY) buffer meshletIndexOffsetBuffer {
    uint meshletIndexOffset[];
  };

//////////////////////////////////////////////////////////////////////////
// INPUT

uint baseID = gl_WorkGroupID.x * NVMESHLET_PER_TASK;
uint laneID = gl_LocalInvocationID.x;

//////////////////////////////////////////////////////////////////////////
// OUTPUT

struct IndirectCommand
{
  uint      indexCount;
  uint      instanceCount;
  uint      firstIndex;
  uint      vertexOffset;
  uint      firstInstance;
};

layout(std430, binding = 2, set = DSET_GEOMETRY) buffer indirectCommandBuffer {
  IndirectCommand indirectCommand[];
};

//////////////////////////////////////////////////////////////////////////
// UTILS

#include "nvmeshlet_utils.glsl"

/////////////////////////////////////////////////
// EXECUTION

void main()
{
  baseID += drawRange.x;
  
  uint outMeshletsCount = 0;
  
  uint  meshletLocal  = laneID;
  uint  meshletGlobal = baseID + meshletLocal;
  uint  finalIndex = min(meshletGlobal, drawRange.y);
  uvec4 desc          = meshletDescs[finalIndex + geometryOffsets.x];

  bool render = !(meshletGlobal > drawRange.y || earlyCull(desc, object));

  if (render)
  {
    indirectCommand[finalIndex + geometryOffsets.w].indexCount = getMeshletNumTriangles(desc) * 3;
    indirectCommand[finalIndex + geometryOffsets.w].instanceCount = 1;
    indirectCommand[finalIndex + geometryOffsets.w].firstIndex = meshletIndexOffset[finalIndex + geometryOffsets.z];
    indirectCommand[finalIndex + geometryOffsets.w].vertexOffset = 0;
    indirectCommand[finalIndex + geometryOffsets.w].firstInstance = 0;
  }
}