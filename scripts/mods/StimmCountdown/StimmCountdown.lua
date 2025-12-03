local mod = get_mod("StimmCountdown")

local UIWidget = require("scripts/managers/ui/ui_widget")
local UIHudSettings = require("scripts/settings/ui/ui_hud_settings")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")

-- Константы
local STIMM_BUFF_NAME = "syringe_broker_buff"
local STIMM_SLOT_NAME = "slot_pocketable_small"
local STIMM_ABILITY_TYPE = "pocketable_ability"

-- Цвета из игры
local ACTIVE_COLOR = UIHudSettings.color_tint_main_1  -- Светлый (как кол-во гранат)
local COOLDOWN_COLOR = UIHudSettings.color_tint_alert_2  -- Красный

-- Добавляем виджет в определения родителя (как в train_timer)
local add_definitions = function(definitions)
	if not definitions then
		return
	end

	definitions.scenegraph_definition = definitions.scenegraph_definition or {}
	definitions.widget_definitions = definitions.widget_definitions or {}

	-- Стиль текста таймера (как гранаты)
	local stimm_timer_text_style = table.clone(UIFontSettings.hud_body)
	stimm_timer_text_style.font_type = "machine_medium"
	stimm_timer_text_style.font_size = 30
	stimm_timer_text_style.drop_shadow = true
	stimm_timer_text_style.text_horizontal_alignment = "right"
	stimm_timer_text_style.text_vertical_alignment = "center"
	stimm_timer_text_style.text_color = table.clone(COOLDOWN_COLOR)
	stimm_timer_text_style.offset = { -60, 0, 10 }

	-- Виджет таймера (использует существующий scenegraph "background")
	definitions.widget_definitions.stimm_timer = UIWidget.create_definition({
		{
			visible = false,
			pass_type = "text",
			style_id = "text",
			value = "",
			value_id = "text",
			style = stimm_timer_text_style,
		},
	}, "background")
end

-- Хук для добавления виджета в определения
mod:hook_require(
	"scripts/ui/hud/elements/player_weapon/hud_element_player_weapon_definitions",
	function(definitions)
		add_definitions(definitions)
	end
)

-- Проверка, является ли игрок классом Broker (Hive Scum)
local function is_broker_class(player)
	if not player then
		return false
	end

	local profile = player:profile()
	if not profile then
		return false
	end

	local archetype = profile.archetype
	return archetype and archetype.name == "broker"
end

-- Найти баф и получить оставшееся время
local function get_buff_remaining_time(buff_extension, buff_template_name)
	if not buff_extension then
		return 0
	end

	local buffs_by_index = buff_extension._buffs_by_index
	if not buffs_by_index then
		return 0
	end

	local timer = 0
	for _, buff in pairs(buffs_by_index) do
		local template = buff:template()
		if template and template.name == buff_template_name then
			local remaining = buff:duration_progress() or 1
			local duration = buff:duration() or 15
			timer = math.max(timer, duration * remaining)
		end
	end

	return timer
end

-- Обновляем таймер
mod:hook_safe("HudElementPlayerWeapon", "update", function(self, dt, t, ui_renderer, render_settings, input_service)
	-- Проверяем что это слот стима
	if self._slot_name ~= STIMM_SLOT_NAME then
		return
	end

	-- Получаем виджет из _widgets_by_name (как в train_timer)
	local widget = self._widgets_by_name and self._widgets_by_name.stimm_timer
	if not widget then
		return
	end

	local data = self._data
	if not data then
		widget.content.visible = false
		return
	end

	local player = data.player
	if not player or not is_broker_class(player) then
		widget.content.visible = false
		return
	end

	local player_unit = player.player_unit
	if not player_unit or not ALIVE[player_unit] then
		widget.content.visible = false
		return
	end

	local buff_extension = ScriptUnit.has_extension(player_unit, "buff_system")
	if not buff_extension then
		widget.content.visible = false
		return
	end

	local display_text = ""
	local display_color = COOLDOWN_COLOR
	local should_show = false

	-- Формат вывода
	local show_decimals = mod:get("show_decimals") ~= false

	-- Проверяем активный баф стима
	local remaining_buff_time = get_buff_remaining_time(buff_extension, STIMM_BUFF_NAME)

	if remaining_buff_time and remaining_buff_time >= 0.05 and mod:get("show_active") ~= false then
		-- Стим активен
		if show_decimals then
			display_text = string.format("%.1f", remaining_buff_time)
		else
			display_text = string.format("%.0f", math.ceil(remaining_buff_time))
		end
		display_color = ACTIVE_COLOR
		should_show = true
	elseif mod:get("show_cooldown") ~= false then
		-- Проверяем кулдаун
		local ability_extension = self._ability_extension
		if ability_extension then
			local remaining_cooldown = ability_extension:remaining_ability_cooldown(STIMM_ABILITY_TYPE)

			if remaining_cooldown and remaining_cooldown >= 0.05 then
				if show_decimals then
					display_text = string.format("%.1f", remaining_cooldown)
				else
					display_text = string.format("%.0f", math.ceil(remaining_cooldown))
				end
				display_color = COOLDOWN_COLOR
				should_show = true
			end
		end
	end

	-- Скрываем виджет если не должно показываться
	if not should_show then
		widget.content.text = ""
		widget.content.visible = false
		-- Устанавливаем alpha = 0 чтобы скрыть уже нарисованный виджет
		widget.style.text.text_color[1] = 0
		widget.dirty = true
		return
	end

	-- Обновляем виджет
	widget.content.text = display_text
	widget.content.visible = true
	-- Устанавливаем цвет
	widget.style.text.text_color[1] = display_color[1]
	widget.style.text.text_color[2] = display_color[2]
	widget.style.text.text_color[3] = display_color[3]
	widget.style.text.text_color[4] = display_color[4]

	-- Синхронизируем позицию с height_offset слота (как другие виджеты)
	local height_offset = self._height_offset or 0
	-- Обновляем только Y offset для синхронизации с позицией слота
	widget.style.text.offset[2] = height_offset

	widget.dirty = true
end)
