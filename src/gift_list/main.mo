import Error "mo:base/Error";
import Option "mo:base/Option";
import Buffer "mo:base/Buffer";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Server "mo:server";

actor GiftList {
  type Request = Server.Request;
  type Response = Server.Response;
  type ResponseClass = Server.ResponseClass;
  stable var serializedEntries : Server.SerializedEntries = ([], [], []);
  var server = Server.Server({ serializedEntries });

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
    items := Buffer.toArray(buf);
    let _ = server.cache.pruneAll();
    return ();
  };

  public query func getGifts() : async [Gift] {
    Debug.print("Gifts" # debug_show items[0]);
    return items;
  };

  public query func getGift(id : Text) : async ?Gift {
    Array.find<Gift>(items, func(x : Gift) { return x.id == id });
  };

  public func updateGift(id : Text, status : Status) : async Result.Result<(), Text> {
    update_gift(id, status);
  };

  private func update_gift(id : Text, status : Status) : Result.Result<(), Text> {
    ignore server.cache.pruneAll();
    let buf = Buffer.Buffer<Gift>(controllers.size());
    for (gift in Array.vals(items)) {
      if (gift.id == id) {
        if (gift.status == #bought and status == #bought) {
          return #ok ();
        };
        if (gift.status == #unbought and status == #unbought) {
          return #ok ();
        };
        buf.add({
          id = id;
          status = status;
          // ignore modifiedBy
          modifiedBy = null;
        });
      } else {
        buf.add(gift);
      };
    };
    items := Buffer.toArray(buf);
    #ok(());
  };

  func jsonGifts() : Text {
    var result = "[";
    var count = 0;
    for (item in Iter.fromArray(items)) {
      count := count + 1;
      result := result # formatGift(item);
      // add a comma if not the last item
      if (count < items.size()) {
        result := result # ",";
      };
    };
    result := result # "]";
    result;
  };

  func formatGift(gift : Gift) : Text {
    return "{\"id\":\""
    # gift.id
    # "\",\"status\":\""
    # (if (gift.status == #bought) { "bought" } else { "unbought" })
    # "\"}";
  };

  server.get(
    "/gifts",
    func(req : Request, res : ResponseClass) : async Response {
      let gifts = jsonGifts();
      Debug.print("Gifts" # debug_show gifts);

      Debug.print("path" # debug_show req.url.path);

      let expiry = { nanoseconds = Int.abs(Time.now() + 100) };
      res.json({
        status_code = 200;
        body = gifts;
        cache_strategy = #expireAfter expiry;
      });
    },
  );

  server.get(
    "/gifts/:id",
    func(req : Request, res : ResponseClass) : async Response {
      ignore do ? {

        let id = req.params!.get("id")!;
        let gift = (await getGift(id))!;
        let expiry = { nanoseconds = Int.abs(Time.now() + 100) };
        return res.json({
          status_code = 200;
          body = formatGift(gift);
          cache_strategy = #expireAfter expiry;
        });
      };
      res.json({
        status_code = 404;
        body = "Gift not found";
        cache_strategy = #default;
      });
    },
  );

  server.post(
    "/gifts/:id/toggle",
    func(req : Request, res : ResponseClass) : async Response {
      ignore do ? {
        let id = req.params!.get("id")!;
        let status = req.body!.text();
        let gift = (await getGift(id))!;
        // toggle status
        let newStatus = if (gift.status == #bought) { #unbought } else { #bought };
        let result = await updateGift(id, newStatus);
        let newGift = (await getGift(id))!;
        switch (result) {
          case (#ok _) {
            return res.json({
              status_code = 200;
              body = formatGift(newGift);
              cache_strategy = #noCache;
            });
          };
          case (#err msg) {
            return res.json({
              status_code = 400;
              body = msg;
              cache_strategy = #noCache;
            });
          };
        };
      };
      res.json({
        status_code = 404;
        body = "Gift not found";
        cache_strategy = #noCache;
      });
    },
  );

  /*
     * http request hooks
     */
  public query func http_request(req : Server.HttpRequest) : async Server.HttpResponse {
    server.http_request(req);
  };
  public func http_request_update(req : Server.HttpRequest) : async Server.HttpResponse {
    await server.http_request_update(req);
  };

  /*
     * upgrade hooks
     */
  system func preupgrade() {
    serializedEntries := server.entries();
  };

  system func postupgrade() {
    ignore server.cache.pruneAll();
  };

  public func empty_cache() : async () {
    for (key in server.cache.keys()) {
      server.cache.delete(key);
    };
  };
};
