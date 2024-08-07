import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Error "mo:base/Error";
import Option "mo:base/Option";
import Buffer "mo:base/Buffer";
import Result "mo:base/Result";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import IC "mo:management-canister";

actor GiftList {

  type Status = {
    #bought;
    #unbought;
  };
  type Gift = {
    id : Text;
    status : Status;
    modifiedBy : ?Principal;
  };

  stable var items : [Gift] = [];
  stable var controllers : [Principal] = [];

  public func registerGift(id : Text) : async () {
    let buf = Buffer.Buffer<Gift>(items.size() + 1);
      let duplicate = Array.find<Gift>(items, func(x) { return x.id == id });
      if (Option.isSome(duplicate)) {
        throw Error.reject("Error: duplicate gift. Use a new ID");
      };

      if (items.size() > 0) {
        for (i in items.vals()) {
          Debug.print(debug_show i);
          buf.add(i);
        };
      };
      buf.add({
        id;
        status = #unbought;
        modifiedBy = null;
      });
      items := buf.toArray();
      return ();
  };

  public query func getGifts() : async [Gift] {
    Debug.print("Gifts" # debug_show items[0]);
    return items;
  };

  public query func getGift(id : Text) : async ?Gift {
    Array.find<Gift>(items, func(x : Gift) { return x.id == id });
  };

  public shared ({ caller }) func updateGift(id : Text, status : Status) : async Result.Result<(), Text> {

    let buf = Buffer.Buffer<Gift>(controllers.size());
    for (gift in Array.vals(items)) {
      if (gift.id == id) {
        if (gift.status == #bought and status == #bought) {
          return #err("Already bought");
        };
        if (gift.status == #unbought and status == #unbought) {
          return #err("Already unbought");
        };
        buf.add({
          id = id;
          status = status;
          modifiedBy = ?caller;
        });
      } else {
        buf.add(gift);
      };
    };
    items := buf.toArray();

    #ok(());
  };

  public func getControllers() : async [Principal] {
    let management : IC.Self = actor ("aaaaa-aa");
    let status = await management.canister_status({
      canister_id = Principal.fromActor(GiftList);
    });
    controllers := status.settings.controllers;
    return controllers;
  };

  public func greet(name : Text) : async Text {
    return "Hello, " # name # "!";
  };
};
