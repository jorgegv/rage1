build-minimal:
	@$(MAKE) -s clean
	@$(MAKE) -s config-minimal
	@$(MAKE) -s data
	@$(MAKE) -s -j8 all

config-minimal:
	@$(MAKE) -s clean-config
	@-mkdir -p $(GAME_SRC_DIR)/ $(GAME_DATA_DIR)/ $(GENERATED_DIR)/
	@cp -r minimal_game/game_data/* $(GAME_DATA_DIR)
	@cp -r minimal_game/game_src/* $(GAME_SRC_DIR)
	@echo "Build config: MINIMAL GAME - Target: $(ZX_TARGET)K"
