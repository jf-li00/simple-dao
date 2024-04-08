module mydao::GovernanceCoin {
    // === Imports ===
    use sui::{
        coin::{self, Coin, TreasuryCap},
        object::{self, UID},
        tx_context::{self, TxContext},
        transfer,
        test_scenario,
    };
    use std::debug;

    // === Constants ===
    const INITIAL_OFFER: u64 = 1_000_000_000_000_000_000;

    // === Structs ===
    // Corrected struct name to upper case
    public struct GOVERNANCECOIN {
        // Added the drop trait for automatic cleanup
    }

    // === Public-Mutative Functions ===
    // Corrected function name to init (lowercase)
    public fun init(witness: GOVERNANCECOIN, ctx: &mut TxContext) {
        let (mut treasury_cap, metadata) = coin::create_currency(
            witness,
            8,
            b"GC",
            b"Governance Coin",
            b"Governance Coin for MyDAO",
            None,
            ctx,
        );

        coin::mint_and_transfer(&mut treasury_cap, INITIAL_OFFER, tx_context::sender(ctx), ctx);

        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
        transfer::public_freeze_object(metadata);
    }

    // === Test Functions ===
    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        let witness = GOVERNANCECOIN {};
        init(witness, ctx);
    }

    #[test]
    fun test_init_and_mint() {
        let secondary_offer = 100;
        let (alice, bob, carol) = (@0x10, @0x20, @0x30);

        let mut scenario = test_scenario::begin(alice);

        // First transaction, init the gov coin.
        {
            scenario.next_tx(bob);
            let ctx = scenario.ctx();
            let witness = GOVERNANCECOIN {};
            init(witness, ctx);
        }

        // Second transaction, mint some coins
        {
            scenario.next_tx(bob);

            // Test the initial
            let coin = scenario.take_from_address::<Coin<GOVERNANCECOIN>>(bob);
            assert!(coin.value() == INITIAL_OFFER, 0);
            scenario.return_to_address(bob, coin);

            let mut treasury_cap: TreasuryCap<GOVERNANCECOIN> = scenario.take_from_sender();

            debug::print(&treasury_cap);

            coin::mint_and_transfer(&mut treasury_cap, secondary_offer, carol, scenario.ctx());
            assert!(treasury_cap.total_supply() == INITIAL_OFFER + secondary_offer, 0);

            debug::print(&treasury_cap);

            scenario.return_to_sender(treasury_cap);
        }

        scenario.end();
    }
}
