import { defineContractComponents } from "./contractComponents";
import { world } from "./world";
import { DojoProvider } from "@dojoengine/core";
import { Account, num } from "starknet";
import dev_manifest from "../target/dev/manifest.json";
import prod_manifest from "../target/release/manifest.json";
import * as torii from "@dojoengine/torii-client";
import { createBurner } from "./createBurner";

export type SetupNetworkResult = Awaited<ReturnType<typeof setupNetwork>>;

export async function setupNetwork() {
    const {
        VITE_PUBLIC_WORLD_ADDRESS,
        VITE_PUBLIC_NODE_URL,
        VITE_PUBLIC_TORII,
        VITE_PUBLIC_DEV,
    } = import.meta.env;

    console.log("####### NETWORK DETAILS #######");
    console.table({
        worldAddress: VITE_PUBLIC_WORLD_ADDRESS,
        nodeUrl: VITE_PUBLIC_NODE_URL,
        toriiUrl: VITE_PUBLIC_TORII,
    });

    const provider = new DojoProvider(
        VITE_PUBLIC_WORLD_ADDRESS,
        VITE_PUBLIC_DEV === "true" ? dev_manifest : prod_manifest,
        VITE_PUBLIC_NODE_URL
    );

    const toriiClient = await torii.createClient([], {
        rpcUrl: VITE_PUBLIC_NODE_URL,
        toriiUrl: VITE_PUBLIC_TORII,
        worldAddress: VITE_PUBLIC_WORLD_ADDRESS,
    });

    const { account, burnerManager } = await createBurner();

    return {
        provider,
        world,
        toriiClient,
        account,
        burnerManager,
        contractComponents: defineContractComponents(world),
        execute: async (
            signer: Account,
            contract: string,
            system: string,
            call_data: num.BigNumberish[]
        ) => {
            // console.log("execute ", { contract, system, call_data });
            return provider.execute(signer, contract, system, call_data);
        },
    };
}
