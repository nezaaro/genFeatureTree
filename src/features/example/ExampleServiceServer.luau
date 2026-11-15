local Service = {}

function Service.init(_self: Service)
	print("hi from ExampleServiceServer!")
end

export type Service = typeof(Service) & {}
return Service
