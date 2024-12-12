import "FungibleToken"
import "NonFungibleToken"
import "ExampleNFT"
import "NFTStorefront"

transaction {
    let paymentVault: @FungibleToken.Vault
    let exampleNFTCollection: &ExampleNFT.Collection
    let storefront: &NFTStorefront.Storefront
    let listing: &NFTStorefront.Listing

    prepare(acct: auth(Storage, Capabilities) &Account) {
        // Borrow the storefront reference
        self.storefront = acct.capabilities.borrow<&NFTStorefront.Storefront>(
            NFTStorefront.StorefrontPublicPath
        ) ?? panic("Could not borrow Storefront from provided address")

        // Borrow the listing reference
        self.listing = self.storefront.borrowListing(listingResourceID: 10)
            ?? panic("No Offer with that ID in Storefront")

        // Fetch the sale price
        let price = self.listing.getDetails().salePrice

        // Borrow FlowToken vault and withdraw payment
        let mainFlowVault = acct.capabilities.storage.borrow<&FungibleToken.Vault>(
            from: /storage/MainVault
        ) ?? panic("Cannot borrow FlowToken vault from account storage")
        self.paymentVault <- mainFlowVault.withdraw(amount: price)

        // Borrow the NFT collection receiver reference
        self.exampleNFTCollection = acct.capabilities.borrow<&ExampleNFT.Collection>(
            ExampleNFT.CollectionPublicPath
        ) ?? panic("Cannot borrow NFT collection receiver from account")
    }

    execute {
        // Execute the purchase
        let item <- self.listing.purchase(
            payment: <-self.paymentVault
        )

        // Confirm the token type and deposit the purchased NFT into the buyer's collection
        let nft <- item as! @ExampleNFT.NFT
        self.exampleNFTCollection.deposit(token: <-nft)

        // Cleanup the listing from the storefront
        self.storefront.cleanup(listingResourceID: 10)

        log("Transaction completed successfully")
    }
}