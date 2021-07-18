build-minimal: config-game-minimal
	@make clean
	@make data
	@make flow
	@make -j8 all

config-game-test:
	@rm -rf $(GAME_SRC_DIR)/* $(GAME_DATA_DIR)/*
	@cp -r test_game/game_src/* $(GAME_SRC_DIR)
	@cp -r test_game/game_data/* $(GAME_DATA_DIR)
	@echo "Build config: TEST GAME"

config-game-minimal:
	@rm -rf $(GAME_SRC_DIR)/* $(GAME_DATA_DIR)/*
	@cp -r minimal_game/game_src/* $(GAME_SRC_DIR)
	@cp -r minimal_game/game_data/* $(GAME_DATA_DIR)
	@echo "Build config: MINIMAL GAME"
