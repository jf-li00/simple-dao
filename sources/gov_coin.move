module mydao::GovernanceCoin{
    use sui::coin;
    const INITIAL_OFFER: u64 = 1000000000000000000;


    // One-time witness should be in upper case
    public struct GOVERNANCECOIN has drop{
    }


    fun init(witness:GOVERNANCECOIN,ctx: &mut TxContext) {
        let (mut treasury_cap, metadata) = coin::create_currency(

            witness,
            8,
            b"GC",
            b"Governance Coin",
            b"Governance Coin for MyDAO",
            option::none(),
            ctx
        );


        coin::mint_and_transfer(&mut treasury_cap, INITIAL_OFFER,
        tx_context::sender(ctx), ctx);

        // transfer the `TreasuryCap` to the sender, so they can mint and burn
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));

        // metadata is typically frozen after creation
        transfer::public_freeze_object(metadata);
    }

    #[test_only]
    /// Wrapper of init function, only to be used in tests to simulate the init function
    public fun test_init(ctx: &mut TxContext){
        let witness = GOVERNANCECOIN{};
        init(witness, ctx);
        
    }


    #[test_only] use sui::test_scenario;
    #[test_only] use sui::coin::{TreasuryCap,Coin};
    #[test_only] use std::debug;

    #[test]
    fun test_init_and_mint() {

        let secondary_offer = 100;
        let (alice,bob,carol) = (@0x10,@0x20,@0x30);

        let mut scenario = test_scenario::begin(alice);
        // First transaction, init the gov coin.
        {
            scenario.next_tx(bob);
            // `test_scenario::ctx` returns the `TxContext`
            let ctx = scenario.ctx();
            let witness = GOVERNANCECOIN{};
            init(witness, ctx);
        };



        // Second transaction, mint some coins
        {
            scenario.next_tx(bob);

            // Test the initial 
            let coin = scenario.take_from_address<Coin<GOVERNANCECOIN>>(bob);
            assert!(coin.value() == INITIAL_OFFER, 0);
            test_scenario::return_to_address(bob, coin);
            // extract the TreasuryCap

            let mut treasury_cap:TreasuryCap<GOVERNANCECOIN> =
            test_scenario::take_from_sender(&scenario);
            
            debug::print(&treasury_cap);
            
            
            coin::mint_and_transfer(&mut treasury_cap, secondary_offer, carol,
            scenario.ctx());
            assert!(&treasury_cap.total_supply() == INITIAL_OFFER + secondary_offer, 0);
            debug::print(&treasury_cap);
            scenario.return_to_sender(treasury_cap);
            

        };
        scenario.end();
    }
}

