module mydao::DAO {
    use sui::table::{Table,Self};
    use sui::package::Self;
    use sui::coin::{Self,Coin};
    use sui::event::{Self};
    use mydao::GovernanceCoin::{GOVERNANCECOIN};



    //* ----------Error codes-----------
    // The sender does not have enough balance to vote
    const E_INSUFFICIENT_BALANCE: u64 = 102;
    // Duplicate voting
    const E_DUPLICATE_VOTE: u64 = 103;
    // The vote is not enabled for the proposal
    const E_INSUFFICIENT_VOTES: u64 = 104;
    // The proposal voting has not started yet
    const E_VOTING_NOT_STARTED: u64 = 105;
    // The proposal voting has ended
    const E_VOTING_ENDED: u64 = 106;
    // The proposal voting not ended and cannot be executed
    const E_VOTING_NOT_ENDED: u64 = 107;



    //* ----------Data structures----------
    public struct DAO has drop{

    }

    public struct Proposal has key, store {
        id: UID,
        description: vector<u8>,
        votes_for: u64,
        votes_against: u64,
        // Minimum number of votes required for a proposal to be approved and executed.
        // This includes both 'for' and 'against' votes within a closed interval.
        minimal_votes_required: u64,
        voted:Table<address,bool>,
        // The time when the voting starts and ends, in milliseconds seconds since the Unix epoch
        voting_start: u64,
        voting_end: u64,
        executed: bool,
    }

    // allow list and deny list for proposals, `true` measn allowed, `false`
    // means denied, and `None` means don't care 
    public struct SepcialList has key, store{
        id : UID,
        list : Table<address,bool>,
    }


    //* ----------Events----------
    // Event to record proposal creation
    public struct ProposalCreatedEvent has copy, drop{
        proposal_id: ID,
        description: vector<u8>,
        minimal_votes_required: u64,
        voting_start: u64,
        voting_end: u64,
    }

    // Event to record voting
    public struct VoteCastEvent has copy, drop{
        proposal_id: ID,
        voter: address,
        vote: bool,
        amount: u64,
    }

    // Event to record proposal execution
    public struct ProposalExecutedEvent has copy, drop{
        proposal_id: ID,
    }

    fun init(otw:DAO, ctx: &mut TxContext) {
        package::claim_and_keep(otw,ctx);
        let special_list = SepcialList{
            id: object::new(ctx),
            list: table::new(ctx),
        };
        
        // Transfer the special list resource to the current module
        transfer::public_transfer(special_list, @mydao);
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        let dao = DAO{};
        init(dao,ctx);
    }

    public fun create_proposal(
        ctx: &mut TxContext, 
        description: vector<u8>,
        minimal_votes_required: u64, 
        voting_start: u64, 
        voting_end: u64
    ) {
        let proposal = Proposal {
            id: object::new(ctx),
            description,
            votes_for: 0,
            votes_against: 0,
            minimal_votes_required,
            voted: table::new(ctx),
            executed: false,
            voting_start,
            voting_end,
        };

        event::emit(ProposalCreatedEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
            description,
            minimal_votes_required,
            voting_start,
            voting_end,
        });

        transfer::share_object(proposal);
    }

    public fun vote(
        ctx: &mut TxContext, 
        proposal: &mut Proposal, 
        vote: bool, 
        amount: u64,
        governance_coin : &Coin<GOVERNANCECOIN>
    ) {

        // Ensure the time epoch is within the voting period
        let time_now = tx_context::epoch_timestamp_ms(ctx);
        assure_time_in_voting_period(proposal, time_now);

        let sender = tx_context::sender(ctx);
        // The maximum amount of votes is the governance coin balance of the sender
        let balance = coin::value(governance_coin);
        assert!(balance >= amount, E_INSUFFICIENT_BALANCE);
        
        // Allow only one vote per proposal for an address. 
        assert!(!proposal.voted.contains(sender), E_DUPLICATE_VOTE);


        // Increase the vote count accordingly
        if (vote) {
            proposal.votes_for = proposal.votes_for + amount;
        } else {
            proposal.votes_against = proposal.votes_against + amount;
        };

        proposal.voted.add(sender,vote);

        // Record the vote
        event::emit(VoteCastEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
            voter: sender,
            vote,
            amount,
        });

    }

    public fun execute_proposal(ctx: &mut TxContext, proposal: &mut Proposal) {
        // The proposal can be executed only if the minimal amount of votes is reached
        assert!(total_votes(proposal) >= proposal.minimal_votes_required, E_INSUFFICIENT_VOTES);
        // Ensure the time epoch is within the voting period
        let time_now = tx_context::epoch_timestamp_ms(ctx);
        assert!(time_now > proposal.voting_end, E_VOTING_NOT_ENDED);


        proposal.executed = true;
        event::emit(ProposalExecutedEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
        });
    }

    public fun total_votes(proposal: &Proposal) :u64 {
        return (proposal.votes_for + proposal.votes_against)
    }

    fun assure_time_in_voting_period(proposal: &Proposal, time: u64) {
        assert!(time >= proposal.voting_start, E_VOTING_NOT_STARTED);
        assert!(time <= proposal.voting_end, E_VOTING_ENDED);
    }


    #[test_only] use std::debug;
    #[test_only] use sui::test_scenario;
    #[test_only] use mydao::GovernanceCoin;
    #[test_only] use sui::coin::{TreasuryCap};


    #[test_only] const VOTING_INTERVAL: u64 = 100;
    #[test]
    fun test_dao() {
        let (alice,bob,carol) = (@0x10,@0x20,@0x30);
        let mut scenario = test_scenario::begin(alice);


        // First transaction, init the DAO and gov coin module.
        {
            scenario.next_tx(bob);
            GovernanceCoin::test_init(scenario.ctx());
            test_init(scenario.ctx());
        };


        
        // Second transation, mint some coin for carol and  create a proposal
        {
            scenario.next_tx(bob);
            let mut treasury_cap:TreasuryCap<GOVERNANCECOIN> =
            test_scenario::take_from_sender(&scenario);
            // Let Carol get some token for voting
            coin::mint_and_transfer(&mut treasury_cap, 1000, carol,
            scenario.ctx());
            scenario.return_to_sender(treasury_cap);

            // Create a proposal
            let now = tx_context::epoch_timestamp_ms(scenario.ctx());
            debug::print(&now);
            create_proposal(scenario.ctx(), b"test proposal", 10, now, now+VOTING_INTERVAL );
            //! Cannot use `take_shared` method to get the proposal, the
            //! `assert!(id_opt.is_some(), EEmptyInventory);` statement in
            //! test_scenario.move:342:9 will fial, do not know why.


        };

        // Third transaction, let carol vote for the proposal.
        {
            scenario.next_tx(carol);

            let coin = scenario.take_from_sender<Coin<GOVERNANCECOIN>>();
            let mut proposal = scenario.take_shared<Proposal>();

            vote(scenario.ctx(), &mut proposal, true, 100, &coin);
            debug::print(&proposal);

            scenario.return_to_sender(coin);
            test_scenario::return_shared(proposal);

        };

        // edge case, should not fail.
        {
            scenario.later_epoch(VOTING_INTERVAL ,bob);

            let coin = scenario.take_from_sender<Coin<GOVERNANCECOIN>>();
            let mut proposal = scenario.take_shared<Proposal>();

            vote(scenario.ctx(), &mut proposal, true, 10000, &coin);
            debug::print(&proposal);

            scenario.return_to_sender(coin);
            test_scenario::return_shared(proposal);

        };

        // execute the proposal
        {
            scenario.later_epoch(1,bob);
            let mut proposal = scenario.take_shared<Proposal>();
            execute_proposal(scenario.ctx(), &mut proposal);
            debug::print(&proposal);
            test_scenario::return_shared(proposal);
        };

        scenario.end();
    }
}