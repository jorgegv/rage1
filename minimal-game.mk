build-minimal:
	@$(MYMAKE) -s clean
	@$(MYMAKE) -s config-minimal
	@$(MYMAKE) -s data
	@$(MYMAKE) -s -j8 all

config-minimal:
	@$(MYMAKE) -s clean-config
	@-mkdir -p $(GAME_SRC_DIR)/ $(GAME_DATA_DIR)/ $(GENERATED_DIR)/
	@cp -r minimal_game/game_data/* $(GAME_DATA_DIR)
	@cp -r minimal_game/game_src/* $(GAME_SRC_DIR)
	@echo "Build config: MINIMAL GAME - Target: $(ZX_TARGET)K"
