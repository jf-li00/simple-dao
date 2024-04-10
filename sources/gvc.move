module mydao::gvc{
    use sui::coin;
    const INITIAL_OFFER: u64 = 1000000000000000000;


    // One-time witness should be in upper case
    public struct GVC has drop{
    }
    
    fun init(witness:GVC,ctx: &mut TxContext) {
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
        let witness = GVC{};
        init(witness, ctx);
        
    }
}