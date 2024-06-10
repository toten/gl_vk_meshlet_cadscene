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


#include "renderer.hpp"
#include "resources_vk.hpp"
#include <algorithm>
#include <cassert>

#include "common.h"


namespace meshlettest {

//////////////////////////////////////////////////////////////////////////


class RendererVK : public Renderer
{
public:
  class TypeCmd : public Renderer::Type
  {
    bool                      isAvailable(const nvvk::Context* context) const override { return true; }
    [[nodiscard]] const char* name() const override { return "VK standard"; }
    [[nodiscard]] Renderer*   create() const override
    {
      auto* renderer = new RendererVK();
      return renderer;
    }
    [[nodiscard]] unsigned int priority() const override { return 10; }

    Resources* resources() override { return ResourcesVK::get(); }
  };


public:
  bool init(RenderList* NV_RESTRICT list, Resources* resources, const Config& config) override;
  void deinit() override;
  void draw(const FrameConfig& global) override;


  RendererVK() = default;

private:
  const RenderList* NV_RESTRICT m_list{};
  ResourcesVK* NV_RESTRICT      m_resources{};
  Config                        m_config;

  VkCommandPool   m_cmdPool{};
  VkCommandBuffer m_cmdBuffers[2]{};
  size_t          m_fboChangeID{};
  size_t          m_pipeChangeID{};

  void GenerateCmdBuffers()
  {
    const RenderList::DrawItem* NV_RESTRICT drawItems = m_list->m_drawItems.data();
    size_t                                  numItems  = m_list->m_drawItems.size();

    const ResourcesVK* NV_RESTRICT res     = m_resources;
    const CadSceneVK&              sceneVK = res->m_scene;

    const ResourcesVK::DrawSetup& setup = res->m_setupStandard;

    VkCommandBuffer cmd = res->createCmdBuffer(m_cmdPool, false, false, true);
    res->cmdDynamicState(cmd);

    int lastMaterial = -1;
    int lastGeometry = -1;
    int lastMatrix   = -1;
    int lastChunk    = -1;

    {
      vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, setup.pipeline);
      vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, setup.container.getPipeLayout(), DSET_SCENE, 1,
                              setup.container.at(DSET_SCENE).getSets(), 0, nullptr);
      vkCmdDraw(cmd, 9, 9, 0, 0);
    }

    vkEndCommandBuffer(cmd);

    m_cmdBuffers[0] = cmd;
    m_cmdBuffers[1] = res->createBoundingBoxCmdBuffer(m_cmdPool, m_list);

    m_fboChangeID  = res->m_fboChangeID;
    m_pipeChangeID = res->m_pipeChangeID;
  }

  void DeleteCmdbuffers()
  {
    vkFreeCommandBuffers(m_resources->m_device, m_cmdPool, NV_ARRAY_SIZE(m_cmdBuffers), m_cmdBuffers);
  }
};


static RendererVK::TypeCmd s_type_cmdbuffer_vk;

bool RendererVK::init(RenderList* NV_RESTRICT list, Resources* resources, const Config& config)
{
  m_list      = list;
  m_resources = (ResourcesVK*)resources;
  m_config    = config;

  VkResult                result;
  VkCommandPoolCreateInfo cmdPoolInfo = {VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
  cmdPoolInfo.queueFamilyIndex        = 0;
  result                              = vkCreateCommandPool(m_resources->m_device, &cmdPoolInfo, nullptr, &m_cmdPool);
  assert(result == VK_SUCCESS);

  GenerateCmdBuffers();

  return true;
}

void RendererVK::deinit()
{
  DeleteCmdbuffers();
  vkDestroyCommandPool(m_resources->m_device, m_cmdPool, nullptr);
}

void RendererVK::draw(const FrameConfig& global)
{
  ResourcesVK* NV_RESTRICT res = m_resources;

  if(m_pipeChangeID != res->m_pipeChangeID || m_fboChangeID != res->m_fboChangeID)
  {
    DeleteCmdbuffers();
    GenerateCmdBuffers();
  }

  VkCommandBuffer primary = res->createTempCmdBuffer();

  {
    const nvvk::ProfilerVK::Section profile(res->m_profilerVK, "Render", primary);

    vkCmdUpdateBuffer(primary, res->m_common.viewBuffer, 0, sizeof(SceneData), (const uint32_t*)&global.sceneUbo);
    vkCmdUpdateBuffer(primary, res->m_common.statsBuffer, 0, sizeof(CullStats), (const uint32_t*)&m_list->m_stats);
    res->cmdPipelineBarrier(primary);
    {
      VkMemoryBarrier memBarrier = {VK_STRUCTURE_TYPE_MEMORY_BARRIER};
      memBarrier.srcAccessMask   = VK_ACCESS_TRANSFER_WRITE_BIT;
      memBarrier.dstAccessMask   = VK_ACCESS_SHADER_READ_BIT;
      vkCmdPipelineBarrier(primary, VK_PIPELINE_STAGE_TRANSFER_BIT,
                           (global.meshletBoxes ? VK_PIPELINE_STAGE_GEOMETRY_SHADER_BIT : 0)
                               | VK_PIPELINE_STAGE_VERTEX_SHADER_BIT | VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                           VK_FALSE, 1, &memBarrier, 0, nullptr, 0, nullptr);
    }

    // clear via pass
    res->cmdBeginRenderPass(primary, true, true);
    vkCmdExecuteCommands(primary, global.meshletBoxes ? 2 : 1, m_cmdBuffers);
    vkCmdEndRenderPass(primary);
    res->cmdCopyStats(primary);
  }

  vkEndCommandBuffer(primary);
  res->submissionEnqueue(primary);
}

}  // namespace meshlettest
