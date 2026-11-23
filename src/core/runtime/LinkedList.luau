export type Node = {
	List: Node?,
	Next: Node,
	Previous: Node,
	[string]: any,
}

local listClass = {}
local linkClass = {}

listClass.__index = listClass
linkClass.__index = linkClass

function listClass.new(): Node
	local self = setmetatable({}, listClass) :: any

	self.List = self
	self.Next = self
	self.Previous = self

	return self
end

function listClass:InsertFront(link: {}): Node
	local node = link :: any
	node.Previous = self
	node.Next = self.Next
	self.Next.Previous = node
	self.Next = node

	return setmetatable(link, linkClass) :: any
end

function listClass:InsertAfter(link: {}): Node
	local node = link :: any
	node.Previous = self
	node.Next = self.Next
	self.Next.Previous = node
	self.Next = node

	return setmetatable(link, linkClass) :: any
end

function listClass:InsertBack(link: {}): Node
	local node = link :: any
	node.Next = self
	node.Previous = self.Previous
	self.Previous.Next = node
	self.Previous = node

	return setmetatable(link, linkClass) :: any
end

function listClass:InsertBefore(link: {}): Node
	local node = link :: any
	node.Next = self
	node.Previous = self.Previous
	self.Previous.Next = node
	self.Previous = node

	return setmetatable(link, linkClass) :: any
end

function listClass.GetNext(current: Node, link: Node?): Node?
	local Next = (link or current).Next
	return if Next ~= (link or current) then Next else nil
end

function listClass.GetPrevious(current: Node, link: Node?): Node?
	local Previous = (link or current).Previous
	return if Previous ~= (link or current) then Previous else nil
end

function listClass:IterateForward(link: Node?)
	return listClass.GetNext, self, link
end

function listClass:IterateBackward(link: Node?)
	return listClass.GetPrevious, self, link
end

function listClass:RemoveFirst(): Node?
	local Next = self.Next
	if Next == self then
		return nil
	end

	Next.Previous.Next = Next.Next
	Next.Next.Previous = Next.Previous

	return Next
end

function listClass:RemoveLast(): Node?
	local Previous = self.Previous
	if Previous == self then
		return nil
	end

	Previous.Previous.Next = Previous.Next
	Previous.Next.Previous = Previous.Previous

	return Previous
end

function listClass:RemoveUpTo(link: Node)
	self.Next = link
	link.Previous = self
end

function listClass:RemoveDownTo(link: Node)
	self.Previous = link
	link.Next = self
end

function listClass:RemoveAll()
	self.Next = self
	self.Previous = self
end

function linkClass.InsertAfter(target: Node, new: {}): Node
	local node = new :: any
	node.Previous = target
	node.Next = target.Next
	target.Next.Previous = node
	target.Next = node

	return setmetatable(new, linkClass) :: any
end

function linkClass.InsertBefore(target: Node, new: {}): Node
	local node = new :: any
	node.Next = target
	node.Previous = target.Previous
	target.Previous.Next = node
	target.Previous = node

	return setmetatable(new, linkClass) :: any
end

function linkClass.GetNext(link: Node): Node?
	local Next = link.Next
	return if Next ~= Next.List then Next else nil
end

function linkClass.GetPrevious(link: Node): Node?
	local Previous = link.Previous
	return if Previous ~= Previous.List then Previous else nil
end

function linkClass.Remove(link: Node)
	link.Previous.Next = link.Next
	link.Next.Previous = link.Previous
end

function linkClass.Clean(link: Node)
	setmetatable(link, nil)
	link.Next = nil :: any
	link.Previous = nil :: any
end

return listClass
