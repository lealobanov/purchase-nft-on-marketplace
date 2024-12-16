import "FungibleToken"
import "NonFungibleToken"
import "ExampleNFT"
import "NFTStorefrontV2"

transaction {
    let paymentVault: @{FungibleToken.Vault}
    let exampleNFTCollection: &ExampleNFT.Collection
    let storefront: auth(NFTStorefrontV2.CreateListing) &NFTStorefrontV2.Storefront
    let listing: &{NFTStorefrontV2.ListingPublic}
    var listingResourceId: UInt64

    prepare(acct: auth(Storage, Capabilities, NFTStorefrontV2.CreateListing) &Account) {

        // Create and save the storefront
        let storefront <- NFTStorefrontV2.createStorefront()
        acct.storage.save(<-storefront, to: NFTStorefrontV2.StorefrontStoragePath)

        // Publish the storefront capability to the public path
        let storefrontCap = acct.capabilities.storage.issue<&{NFTStorefrontV2.StorefrontPublic}>(
            NFTStorefrontV2.StorefrontStoragePath
        )
        acct.capabilities.publish(storefrontCap, at: NFTStorefrontV2.StorefrontPublicPath)

        // Borrow the storefront reference using the public capability path
        let storefrontRef = acct.capabilities.borrow<&{NFTStorefrontV2.StorefrontPublic}>(
            NFTStorefrontV2.StorefrontPublicPath
        ) ?? panic("Could not borrow Storefront from provided address")
        // Borrow the storefront reference directly from storage
        self.storefront = acct.storage.borrow<auth(NFTStorefrontV2.CreateListing) &NFTStorefrontV2.Storefront>(
            from: NFTStorefrontV2.StorefrontStoragePath
        ) ?? panic("Could not borrow Storefront with CreateListing authorization from storage")

        // Borrow the NFTMinter from the caller's storage
        let minter = acct.storage.borrow<&ExampleNFT.NFTMinter>(
            from: /storage/exampleNFTMinter
        ) ?? panic("Could not borrow the NFT minter reference.")

        // Mint a new NFT with metadata
        let nft <- minter.mintNFT(
            name: "Example NFT",
            description: "Minting a sample NFT",
            thumbnail: "https://example.com/thumbnail.png",
            royalties: [],
            metadata: {
                "Power": "100",
                "Will": "Strong",
                "Determination": "Unyielding"
            },
            
        )

        let nftID = nft.id

        // Borrow the collection from the caller's storage
        let collection = acct.storage.borrow<&ExampleNFT.Collection>(
            from: /storage/exampleNFTCollection
        ) ?? panic("Could not borrow the NFT collection reference.")

        // Deposit the newly minted NFT into the caller's collection
        collection.deposit(token: <-nft)


        let nftProviderCapability = acct.capabilities.storage.issue<auth(NonFungibleToken.Withdraw) &{NonFungibleToken.Collection}>(
            /storage/exampleNFTCollection
        )
        
        // List the NFT
        self.listingResourceId = self.storefront.createListing(
            nftProviderCapability: nftProviderCapability,
            nftType: Type<@ExampleNFT.NFT>(),
            nftID: nftID,
            salePaymentVaultType: Type<@{FungibleToken.Vault}>(),
            saleCuts: [
                NFTStorefrontV2.SaleCut(
                    receiver: acct.capabilities.get<&{FungibleToken.Receiver}>(
                        /public/flowTokenReceiver
                    )!,
                    amount: 1.0
                )
            ],
            marketplacesCapability: nil,
            customID: nil,   
            commissionAmount: 0.0,     
            expiry: UInt64(getCurrentBlock().timestamp + UFix64(60 * 60 * 24))
        )
        log("Listing created successfully")

        // Borrow the listing reference
        self.listing = self.storefront.borrowListing(listingResourceID: self.listingResourceId)
            ?? panic("No Offer with that ID in Storefront")

        // Fetch the sale price
        let price = self.listing.getDetails().salePrice

        // Issue the capability for the FlowToken vault with Withdraw entitlement
        let flowTokenCap = acct.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            /storage/flowTokenVault
        )

        // Withdraw the payment
        let flowTokenVault = flowTokenCap.borrow()
        ?? panic("Failed to borrow FungibleToken.Vault from capability")

        self.paymentVault <- flowTokenVault.withdraw(amount: price)

        // Borrow the NFT collection receiver reference
        let nftCollectionCap = acct.capabilities.borrow<&ExampleNFT.Collection>(
            ExampleNFT.CollectionPublicPath
        ) ?? panic("Cannot borrow NFT collection receiver from account")
        self.exampleNFTCollection = nftCollectionCap
    }

    execute {
        // Execute the purchase
        let item <- self.listing.purchase(
            payment: <-self.paymentVault,
            commissionRecipient: nil 
        )

        // Confirm the token type and deposit the purchased NFT into the buyer's collection
        let nft <- item as! @ExampleNFT.NFT
        self.exampleNFTCollection.deposit(token: <-nft)

        log("Transaction completed successfully")
    }
}